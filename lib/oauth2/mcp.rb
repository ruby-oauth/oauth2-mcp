# frozen_string_literal: true

require "version_gem"

require "json"
require "uri"

require "jwt"
require "oauth2"

require_relative "mcp/version"

module OAuth2
  module MCP
    class Error < StandardError; end

    class ConfigurationError < Error; end

    class InvalidToken < Error; end

    # Normalized token claims returned by provider-specific validators.
    class TokenClaims
      attr_reader :subject, :scopes, :audience, :issuer, :expires_at, :raw

      def initialize(subject: nil, scopes: [], audience: [], **claims)
        @subject = subject
        @scopes = Array(scopes).flat_map { |scope| scope.to_s.split(/\s+/) }.reject(&:empty?).freeze
        @audience = Array(audience).map(&:to_s).reject(&:empty?).freeze
        @issuer = claims[:issuer]
        @expires_at = claims[:expires_at]
        @raw = (claims[:raw] || {}).freeze
      end

      def self.from_hash(hash)
        new(
          subject: first_value(hash, :subject, "subject", :sub, "sub"),
          scopes: first_value(hash, :scopes, "scopes", :scope, "scope") || [],
          audience: first_value(hash, :audience, "audience", :aud, "aud") || [],
          issuer: first_value(hash, :issuer, "issuer", :iss, "iss"),
          expires_at: first_value(hash, :expires_at, "expires_at", :exp, "exp"),
          raw: hash,
        )
      end

      def self.first_value(hash, *keys)
        keys.each do |key|
          return hash[key] if hash.key?(key)
        end
        nil
      end
      private_class_method :first_value

      def expired?(now: Time.now)
        return false unless expires_at

        Time.at(expires_at.to_i) <= now
      end

      def scopes_include?(required_scopes)
        (Array(required_scopes).map(&:to_s) - scopes).empty?
      end

      def audience_includes?(resource)
        audience.include?(resource.to_s)
      end
    end

    # Extracts Bearer tokens from Rack-style env hashes or request header hashes.
    class BearerToken
      AUTHORIZATION_HEADER = "authorization"

      def self.extract(request)
        header = authorization_header(request)
        scheme, token = header.to_s.split(/\s+/, 2)
        return unless scheme&.casecmp("bearer")&.zero?

        token.to_s.empty? ? nil : token
      end

      def self.authorization_header(request)
        headers = request.fetch(:headers, request.fetch("headers", nil)) if request.respond_to?(:fetch)
        header = header_value(headers, AUTHORIZATION_HEADER)
        return header if header

        header_value(request, "HTTP_AUTHORIZATION") || header_value(request, "Authorization")
      end

      def self.header_value(headers, name)
        return unless headers.respond_to?(:each)

        headers.each do |key, value|
          return value if key.to_s.casecmp(name).zero?
        end
        nil
      end

      private_class_method :authorization_header, :header_value
    end

    # Maps validated OAuth scopes into application capabilities.
    class ScopeMapper
      attr_reader :mapping

      def initialize(mapping:, passthrough: false)
        @mapping = normalize_mapping(mapping)
        @passthrough = passthrough
        raise ConfigurationError, "scope mapping must not be empty" if @mapping.empty? && !@passthrough
      end

      def capabilities_for(claims_or_scopes)
        scopes = claims_or_scopes.respond_to?(:scopes) ? claims_or_scopes.scopes : claims_or_scopes
        Array(scopes).flat_map { |scope| capabilities_for_scope(scope) }.uniq.freeze
      end

      private

      def capabilities_for_scope(scope)
        mapped = mapping.fetch(scope.to_s, [])
        return mapped unless mapped.empty? && @passthrough

        [scope.to_s]
      end

      def normalize_mapping(mapping)
        mapping.each_with_object({}) do |(scope, capabilities), result|
          result[scope.to_s] = Array(capabilities).map(&:to_s).reject(&:empty?)
        end.freeze
      end
    end

    # Validates JWT bearer tokens with a configured JWKS.
    class JWTValidator
      attr_reader :issuer, :audience, :algorithms, :leeway

      def initialize(jwks:, issuer: nil, audience: nil, algorithms: ["RS256"], leeway: 60)
        @jwk_set = build_jwk_set(jwks)
        @issuer = issuer
        @audience = audience
        @algorithms = Array(algorithms).map(&:to_s).freeze
        @leeway = leeway
      end

      def call(token)
        decoded, = JWT.decode(token, nil, true, decode_options)
        TokenClaims.from_hash(decoded)
      rescue JWT::DecodeError => e
        raise InvalidToken, e.message
      end

      private

      def decode_options
        {
          algorithms: algorithms,
          jwks: @jwk_set,
          verify_iss: !issuer.nil?,
          iss: issuer,
          verify_aud: !audience.nil?,
          aud: audience,
          leeway: leeway,
        }
      end

      def build_jwk_set(jwks)
        keys = jwks.fetch(:keys, jwks.fetch("keys", jwks))
        JWT::JWK::Set.new(Array(keys).map { |key| JWT::JWK.import(key) })
      end
    end

    # Fetches OIDC provider metadata and JWKS for MCP token validation.
    class OIDCDiscovery
      WELL_KNOWN_PATH = "/.well-known/openid-configuration"

      attr_reader :issuer, :client

      def initialize(issuer:, client: nil)
        @issuer = issuer.to_s.delete_suffix("/")
        @client = client || OAuth2::Client.new(nil, nil, site: @issuer, raise_errors: true)
      end

      def configuration
        @configuration ||= fetch_json(WELL_KNOWN_PATH)
      end

      def jwks
        @jwks ||= fetch_json(configuration.fetch("jwks_uri"))
      end

      def jwt_validator(audience:, algorithms: nil, leeway: 60)
        JWTValidator.new(
          jwks: jwks,
          issuer: issuer,
          audience: audience,
          algorithms: algorithms || default_algorithms,
          leeway: leeway,
        )
      end

      private

      def default_algorithms
        configured = Array(configuration["id_token_signing_alg_values_supported"])
        configured.empty? ? ["RS256"] : configured
      end

      def fetch_json(path_or_url)
        response = client.request(:get, path_or_url, parse: :json, snaky: false)
        parsed = response.respond_to?(:parsed) ? response.parsed : response
        parsed.respond_to?(:to_h) ? parsed.to_h : parsed
      end
    end

    # Validates opaque bearer tokens through OAuth token introspection.
    class IntrospectionValidator
      attr_reader :client, :introspection_url, :audience, :issuer, :token_type_hint

      def initialize(client:, introspection_url:, audience: nil, issuer: nil, token_type_hint: "access_token")
        @client = client
        @introspection_url = introspection_url
        @audience = audience
        @issuer = issuer
        @token_type_hint = token_type_hint
      end

      def call(token)
        claims = TokenClaims.from_hash(introspect(token))
        raise InvalidToken, "Token audience does not match." if audience && !claims.audience_includes?(audience)
        raise InvalidToken, "Token issuer does not match." if issuer && claims.issuer != issuer

        claims
      end

      private

      def introspect(token)
        parsed = fetch_introspection(token)
        raise InvalidToken, "Token is inactive." unless truthy?(parsed["active"] || parsed[:active])

        parsed
      end

      def fetch_introspection(token)
        response = client.request(:post, introspection_url, request_options(token))
        parsed = response.respond_to?(:parsed) ? response.parsed : response
        parsed.respond_to?(:to_h) ? parsed.to_h : parsed
      end

      def request_options(token)
        {
          body: URI.encode_www_form(token: token, token_type_hint: token_type_hint),
          headers: {"Content-Type" => "application/x-www-form-urlencoded"},
          parse: :json,
          snaky: false,
        }
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end
    end

    # WorkOS AuthKit adapter for MCP resource-server JWT validation.
    class WorkOSAuthKit
      JWKS_PATH = "/oauth2/jwks"

      attr_reader :issuer, :audience, :client, :algorithms, :leeway

      def initialize(audience:, issuer: nil, subdomain: nil, client: nil, **options)
        @issuer = normalize_issuer(issuer: issuer, subdomain: subdomain)
        @audience = audience
        @client = client || OAuth2::Client.new(nil, nil, site: @issuer, raise_errors: true)
        @algorithms = Array(options.fetch(:algorithms, ["RS256"])).map(&:to_s).freeze
        @leeway = options.fetch(:leeway, 60)
      end

      def call(token)
        jwt_validator.call(token)
      end

      def jwt_validator
        @jwt_validator ||= JWTValidator.new(
          jwks: jwks,
          issuer: issuer,
          audience: audience,
          algorithms: algorithms,
          leeway: leeway,
        )
      end

      def jwks
        @jwks ||= fetch_json(JWKS_PATH)
      end

      private

      def normalize_issuer(issuer:, subdomain:)
        return issuer.to_s.delete_suffix("/") if issuer
        return "https://#{subdomain}.authkit.app" if subdomain

        raise ConfigurationError, "issuer or subdomain is required"
      end

      def fetch_json(path_or_url)
        response = client.request(:get, path_or_url, parse: :json, snaky: false)
        parsed = response.respond_to?(:parsed) ? response.parsed : response
        parsed.respond_to?(:to_h) ? parsed.to_h : parsed
      end
    end

    # Rack-compatible middleware for protecting MCP HTTP endpoints.
    class RackMiddleware
      AUTHORIZATION_ENV_KEY = "oauth2.mcp.authorization"

      attr_reader :app, :resource_server, :scopes

      def initialize(app, resource_server:, scopes: [])
        @app = app
        @resource_server = resource_server
        @scopes = scopes
      end

      def call(env)
        result = resource_server.authorize(request: env, scopes: scopes_for(env))
        return unauthorized_response(result) unless result.allowed?

        env[AUTHORIZATION_ENV_KEY] = result
        app.call(env)
      end

      private

      def scopes_for(env)
        scopes.respond_to?(:call) ? scopes.call(env) : scopes
      end

      def unauthorized_response(result)
        [result.status, result.headers, []]
      end
    end

    # Result object returned by resource-server authorization checks.
    class AuthorizationResult
      attr_reader :claims, :capabilities, :status, :error, :error_description, :required_scopes, :challenge

      def self.allow(claims:, capabilities: [])
        new(allowed: true, claims: claims, capabilities: capabilities)
      end

      def self.deny(status:, error:, error_description:, required_scopes:, challenge:)
        new(
          allowed: false,
          status: status,
          error: error,
          error_description: error_description,
          required_scopes: required_scopes,
          challenge: challenge,
        )
      end

      def initialize(allowed:, **attributes)
        @allowed = allowed
        @claims = attributes[:claims]
        @capabilities = Array(attributes[:capabilities]).map(&:to_s).freeze
        @status = attributes[:status]
        @error = attributes[:error]
        @error_description = attributes[:error_description]
        @required_scopes = Array(attributes[:required_scopes]).map(&:to_s).freeze
        @challenge = attributes[:challenge]
      end

      def allowed?
        @allowed
      end

      def headers
        return {} unless challenge

        {"WWW-Authenticate" => challenge.to_header}
      end
    end

    # Provider-neutral MCP protected resource authorization.
    class ResourceServer
      attr_reader :resource_metadata, :resource_metadata_url, :validator, :scope_mapper

      def initialize(resource_metadata:, resource_metadata_url:, validator:, scope_mapper: nil,
        require_resource_audience: true)
        @resource_metadata = resource_metadata
        @resource_metadata_url = resource_metadata_url
        @validator = validator
        @scope_mapper = scope_mapper
        @require_resource_audience = require_resource_audience
      end

      def authorize(request:, scopes: [])
        required_scopes = Array(scopes).map(&:to_s).reject(&:empty?)
        token = BearerToken.extract(request)
        return deny_missing_token(required_scopes) unless token

        claims = validate(token)
        authorize_claims(claims: claims, required_scopes: required_scopes)
      rescue InvalidToken => e
        deny_invalid_token(required_scopes, e.message)
      end

      private

      def authorize_claims(claims:, required_scopes:)
        return deny_invalid_token(required_scopes, "Token is expired.") if claims.expired?
        return deny_invalid_token(required_scopes, audience_error) unless valid_audience?(claims)
        return deny_insufficient_scope(required_scopes) unless claims.scopes_include?(required_scopes)

        AuthorizationResult.allow(claims: claims, capabilities: capabilities_for(claims))
      end

      def capabilities_for(claims)
        return [] unless scope_mapper

        scope_mapper.capabilities_for(claims)
      end

      def validate(token)
        result = validator.respond_to?(:call) ? validator.call(token) : validator.validate(token)
        return result if result.is_a?(TokenClaims)
        raise InvalidToken, "Token validator returned no claims." unless result

        TokenClaims.from_hash(result)
      end

      def valid_audience?(claims)
        return true unless @require_resource_audience

        claims.audience_includes?(resource_metadata.resource)
      end

      def audience_error
        "Token audience does not include this MCP resource."
      end

      def deny_missing_token(required_scopes)
        deny(
          status: 401,
          error: nil,
          error_description: nil,
          required_scopes: required_scopes,
        )
      end

      def deny_invalid_token(required_scopes, description)
        deny(
          status: 401,
          error: "invalid_token",
          error_description: description,
          required_scopes: required_scopes,
        )
      end

      def deny_insufficient_scope(required_scopes)
        deny(
          status: 403,
          error: "insufficient_scope",
          error_description: "Additional scope is required.",
          required_scopes: required_scopes,
        )
      end

      def deny(status:, error:, error_description:, required_scopes:)
        AuthorizationResult.deny(
          status: status,
          error: error,
          error_description: error_description,
          required_scopes: required_scopes,
          challenge: challenge(error: error, error_description: error_description, required_scopes: required_scopes),
        )
      end

      def challenge(error:, error_description:, required_scopes:)
        BearerChallenge.new(
          resource_metadata: resource_metadata_url,
          scope: required_scopes,
          error: error,
          error_description: error_description,
        )
      end
    end

    # Represents OAuth protected-resource metadata for an MCP HTTP endpoint.
    class ProtectedResourceMetadata
      attr_reader :resource, :authorization_servers, :scopes_supported, :metadata

      def initialize(resource:, authorization_servers:, scopes_supported: [], **metadata)
        @resource = normalize_required_uri(resource, "resource")
        @authorization_servers = Array(authorization_servers).map do |server|
          normalize_required_uri(server, "authorization server")
        end.freeze
        raise ConfigurationError, "authorization_servers must not be empty" if @authorization_servers.empty?

        @scopes_supported = Array(scopes_supported).map(&:to_s).freeze
        @metadata = metadata.transform_keys(&:to_sym).freeze
      end

      def to_h
        {
          resource: resource,
          authorization_servers: authorization_servers,
          scopes_supported: scopes_supported,
        }.merge(metadata).compact
      end

      def to_json(*)
        JSON.generate(to_h, *)
      end

      private

      def normalize_required_uri(value, name)
        uri = value.to_s
        raise ConfigurationError, "#{name} must be an absolute HTTPS URI" unless uri.start_with?("https://")

        uri.delete_suffix("/")
      end
    end

    # Formats `WWW-Authenticate` Bearer challenges for MCP HTTP responses.
    class BearerChallenge
      attr_reader :resource_metadata, :scope, :error, :error_description

      def initialize(resource_metadata:, scope: nil, error: nil, error_description: nil)
        @resource_metadata = resource_metadata.to_s
        @scope = scope
        @error = error
        @error_description = error_description
      end

      def to_header
        parameters = {
          resource_metadata: resource_metadata,
          scope: format_scope(scope),
          error: error,
          error_description: error_description,
        }.compact

        "Bearer #{parameters.map { |key, value| %(#{key}="#{escape(value)}") }.join(", ")}"
      end

      private

      def format_scope(value)
        return if value.nil?

        Array(value).map(&:to_s).reject(&:empty?).join(" ")
      end

      def escape(value)
        value.to_s.gsub("\\", "\\\\\\").gsub('"', '\"')
      end
    end
  end
end

OAuth2::MCP::Version.class_eval do
  extend VersionGem::Basic
end
