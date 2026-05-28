# frozen_string_literal: true

RSpec.describe OAuth2::MCP do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  it "loads on top of the oauth2 gem" do
    expect(OAuth2::Client).to be_a(Class)
  end
end

RSpec.describe OAuth2::MCP::ProtectedResourceMetadata do
  it "builds protected resource metadata" do
    metadata = described_class.new(
      resource: "https://brain.example.com/mcp/",
      authorization_servers: ["https://auth.example.com/"],
      scopes_supported: %w[memory.read memory.write],
    )

    expect(metadata.to_h).to eq(
      resource: "https://brain.example.com/mcp",
      authorization_servers: ["https://auth.example.com"],
      scopes_supported: %w[memory.read memory.write],
    )
    expect(JSON.parse(metadata.to_json)).to include("resource" => "https://brain.example.com/mcp")
  end

  it "rejects non-https resource metadata URIs" do
    expect do
      described_class.new(
        resource: "http://brain.example.com/mcp",
        authorization_servers: ["https://auth.example.com"],
      )
    end.to raise_error(OAuth2::MCP::ConfigurationError, /resource/)
  end

  it "rejects empty authorization server lists" do
    expect do
      described_class.new(
        resource: "https://brain.example.com/mcp",
        authorization_servers: [],
      )
    end.to raise_error(OAuth2::MCP::ConfigurationError, /authorization_servers/)
  end
end

RSpec.describe OAuth2::MCP::BearerChallenge do
  it "builds bearer challenges with MCP protected resource metadata" do
    header = described_class.new(
      resource_metadata: "https://brain.example.com/.well-known/oauth-protected-resource/mcp",
      scope: %w[memory.read memory.write],
      error: "insufficient_scope",
      error_description: "Additional memory scopes are required",
    ).to_header

    expect(header).to eq(
      'Bearer resource_metadata="https://brain.example.com/.well-known/oauth-protected-resource/mcp", ' \
        'scope="memory.read memory.write", error="insufficient_scope", ' \
        'error_description="Additional memory scopes are required"',
    )
  end
end

RSpec.describe OAuth2::MCP::BearerToken do
  it "extracts bearer tokens from request headers" do
    token = described_class.extract(headers: {"Authorization" => "Bearer token-1"})

    expect(token).to eq("token-1")
  end

  it "extracts bearer tokens from Rack env authorization headers" do
    token = described_class.extract("HTTP_AUTHORIZATION" => "Bearer token-2")

    expect(token).to eq("token-2")
  end

  it "ignores non-bearer authorization headers" do
    token = described_class.extract(headers: {"Authorization" => "Basic abc"})

    expect(token).to be_nil
  end

  it "ignores bearer headers without a token" do
    token = described_class.extract(headers: {"Authorization" => "Bearer"})

    expect(token).to be_nil
  end

  it "returns nil for request objects without enumerable headers" do
    token = described_class.extract(Object.new)

    expect(token).to be_nil
  end
end

RSpec.describe OAuth2::MCP::TokenClaims do
  it "normalizes scope strings and audience claims" do
    claims = described_class.from_hash(
      "sub" => "user-1",
      "scope" => "memory.read memory.write",
      "aud" => "https://brain.example.com/mcp",
    )

    expect(claims.subject).to eq("user-1")
    expect(claims.scopes).to eq(%w[memory.read memory.write])
    expect(claims.audience).to eq(["https://brain.example.com/mcp"])
  end

  it "detects expired claims" do
    claims = described_class.new(expires_at: Time.now.to_i - 1)

    expect(claims).to be_expired
  end
end

RSpec.describe OAuth2::MCP::ScopeMapper do
  it "maps validated token scopes into application capabilities" do
    mapper = described_class.new(
      mapping: {
        "memory.read" => "documents_read",
        "memory.admin" => %w[memory_repair_scope_binding memory_tombstone],
      },
    )

    capabilities = mapper.capabilities_for(%w[memory.read memory.admin unknown.scope])

    expect(capabilities).to eq(%w[documents_read memory_repair_scope_binding memory_tombstone])
  end

  it "passes scopes through when configured" do
    mapper = described_class.new(mapping: {"memory.read" => "documents_read"}, passthrough: true)

    capabilities = mapper.capabilities_for(%w[memory.read memory.write])

    expect(capabilities).to eq(%w[documents_read memory.write])
  end

  it "requires an explicit mapping unless passthrough is enabled" do
    expect do
      described_class.new(mapping: {})
    end.to raise_error(OAuth2::MCP::ConfigurationError, /mapping/)
  end
end

RSpec.describe OAuth2::MCP::JWTValidator do # rubocop:disable Metrics/BlockLength
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa_key.public_key, kid: "key-1") }
  let(:jwks) { {"keys" => [jwk.export]} }

  it "validates JWTs with configured JWKS and returns normalized claims" do
    token = JWT.encode(
      {
        sub: "user-1",
        scope: "memory.read",
        aud: "https://brain.example.com/mcp",
        iss: "https://auth.example.com",
        exp: Time.now.to_i + 60,
      },
      rsa_key,
      "RS256",
      kid: "key-1",
    )

    claims = described_class.new(
      jwks: jwks,
      issuer: "https://auth.example.com",
      audience: "https://brain.example.com/mcp",
    ).call(token)

    expect(claims.subject).to eq("user-1")
    expect(claims.scopes).to eq(["memory.read"])
    expect(claims.audience).to eq(["https://brain.example.com/mcp"])
  end

  it "raises InvalidToken for invalid JWT claims" do
    token = JWT.encode(
      {
        sub: "user-1",
        aud: "https://other.example.com/mcp",
        iss: "https://auth.example.com",
        exp: Time.now.to_i + 60,
      },
      rsa_key,
      "RS256",
      kid: "key-1",
    )

    validator = described_class.new(
      jwks: jwks,
      issuer: "https://auth.example.com",
      audience: "https://brain.example.com/mcp",
    )

    expect { validator.call(token) }.to raise_error(OAuth2::MCP::InvalidToken)
  end
end

RSpec.describe OAuth2::MCP::OIDCDiscovery do # rubocop:disable Metrics/BlockLength
  it "fetches provider metadata and builds a JWT validator" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/.well-known/openid-configuration",
      parse: :json,
      snaky: false,
    ).and_return(
      response(
        "jwks_uri" => "https://auth.example.com/jwks.json",
        "id_token_signing_alg_values_supported" => ["RS256"],
      ),
    )
    allow(client).to receive(:request).with(
      :get,
      "https://auth.example.com/jwks.json",
      parse: :json,
      snaky: false,
    ).and_return(response("keys" => []))

    discovery = described_class.new(issuer: "https://auth.example.com/", client: client)

    expect(discovery.configuration.fetch("jwks_uri")).to eq("https://auth.example.com/jwks.json")
    expect(discovery.jwks).to eq("keys" => [])
    expect(discovery.jwt_validator(audience: "https://brain.example.com/mcp")).to be_a(OAuth2::MCP::JWTValidator)
  end

  it "uses default algorithms when provider metadata omits supported algorithms" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/.well-known/openid-configuration",
      parse: :json,
      snaky: false,
    ).and_return(
      "jwks_uri" => "https://auth.example.com/jwks.json",
    )
    allow(client).to receive(:request).with(
      :get,
      "https://auth.example.com/jwks.json",
      parse: :json,
      snaky: false,
    ).and_return("keys" => [])

    discovery = described_class.new(issuer: "https://auth.example.com/", client: client)

    expect(discovery.jwt_validator(audience: "https://brain.example.com/mcp").algorithms).to eq(["RS256"])
  end

  it "returns raw provider responses when they cannot be coerced to hashes" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/.well-known/openid-configuration",
      parse: :json,
      snaky: false,
    ).and_return("not-json")

    discovery = described_class.new(issuer: "https://auth.example.com/", client: client)

    expect(discovery.configuration).to eq("not-json")
  end

  def response(body)
    instance_double(OAuth2::Response, parsed: body)
  end
end

RSpec.describe OAuth2::MCP::IntrospectionValidator do # rubocop:disable Metrics/BlockLength
  it "validates active introspection responses" do
    client = introspection_client(
      "active" => true,
      "sub" => "user-1",
      "scope" => "memory.read",
      "aud" => "https://brain.example.com/mcp",
      "iss" => "https://auth.example.com",
    )

    claims = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
      audience: "https://brain.example.com/mcp",
      issuer: "https://auth.example.com",
    ).call("token-1")

    expect(claims.subject).to eq("user-1")
    expect(claims.scopes).to eq(["memory.read"])
  end

  it "rejects inactive introspection responses" do
    client = introspection_client("active" => false)
    validator = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
    )

    expect { validator.call("token-1") }.to raise_error(OAuth2::MCP::InvalidToken, /inactive/)
  end

  it "rejects introspection responses with mismatched audience" do
    client = introspection_client(
      "active" => true,
      "aud" => "https://other.example.com/mcp",
    )
    validator = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
      audience: "https://brain.example.com/mcp",
    )

    expect { validator.call("token-1") }.to raise_error(OAuth2::MCP::InvalidToken, /audience/)
  end

  it "rejects introspection responses with mismatched issuer" do
    client = introspection_client(
      active: true,
      iss: "https://other.example.com",
    )
    validator = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
      issuer: "https://auth.example.com",
    )

    expect { validator.call("token-1") }.to raise_error(OAuth2::MCP::InvalidToken, /issuer/)
  end

  it "accepts raw hash introspection responses" do
    client = introspection_client(
      "active" => "true",
      "sub" => "user-1",
    )
    validator = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
    )

    expect(validator.call("token-1").subject).to eq("user-1")
  end

  it "rejects raw non-hash introspection responses as inactive" do
    client = introspection_client("not-json")
    validator = described_class.new(
      client: client,
      introspection_url: "https://auth.example.com/oauth2/introspection",
    )

    expect { validator.call("token-1") }.to raise_error(OAuth2::MCP::InvalidToken, /inactive/)
  end

  def introspection_client(body)
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :post,
      "https://auth.example.com/oauth2/introspection",
      hash_including(parse: :json, snaky: false),
    ).and_return(introspection_response(body))
    client
  end

  def introspection_response(body)
    if body.is_a?(Hash) && body.key?("active")
      response(body)
    else
      body
    end
  end

  def response(body)
    instance_double(OAuth2::Response, parsed: body)
  end
end

RSpec.describe OAuth2::MCP::WorkOSAuthKit do
  it "builds a JWT validator from the AuthKit JWKS endpoint" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/oauth2/jwks",
      parse: :json,
      snaky: false,
    ).and_return(response("keys" => []))

    authkit = described_class.new(
      subdomain: "acme",
      audience: "https://brain.example.com/mcp",
      client: client,
    )

    expect(authkit.issuer).to eq("https://acme.authkit.app")
    expect(authkit.jwks).to eq("keys" => [])
    expect(authkit.jwt_validator).to be_a(OAuth2::MCP::JWTValidator)
  end

  it "normalizes explicit issuers and accepts raw JWKS responses" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/oauth2/jwks",
      parse: :json,
      snaky: false,
    ).and_return("keys" => [])

    authkit = described_class.new(
      issuer: "https://login.example.com/",
      audience: "https://brain.example.com/mcp",
      client: client,
    )

    expect(authkit.issuer).to eq("https://login.example.com")
    expect(authkit.jwks).to eq("keys" => [])
  end

  it "delegates token validation through the built JWT validator" do
    authkit = described_class.new(
      issuer: "https://login.example.com/",
      audience: "https://brain.example.com/mcp",
      client: instance_double(OAuth2::Client),
    )
    claims = OAuth2::MCP::TokenClaims.new(subject: "user-1")
    validator = instance_double(OAuth2::MCP::JWTValidator, call: claims)
    allow(authkit).to receive(:jwt_validator).and_return(validator)

    expect(authkit.call("token-1")).to be(claims)
    expect(validator).to have_received(:call).with("token-1")
  end

  it "returns raw AuthKit JWKS responses when they cannot be coerced to hashes" do
    client = instance_double(OAuth2::Client)
    allow(client).to receive(:request).with(
      :get,
      "/oauth2/jwks",
      parse: :json,
      snaky: false,
    ).and_return("not-json")

    authkit = described_class.new(
      issuer: "https://login.example.com/",
      audience: "https://brain.example.com/mcp",
      client: client,
    )

    expect(authkit.jwks).to eq("not-json")
  end

  it "requires either an issuer or an AuthKit subdomain" do
    expect do
      described_class.new(audience: "https://brain.example.com/mcp")
    end.to raise_error(OAuth2::MCP::ConfigurationError, /issuer or subdomain/)
  end

  def response(body)
    instance_double(OAuth2::Response, parsed: body)
  end
end

RSpec.describe OAuth2::MCP::RackMiddleware do # rubocop:disable Metrics/BlockLength
  it "stores authorization results in the Rack env for allowed requests" do
    app = lambda do |env|
      result = env.fetch(OAuth2::MCP::RackMiddleware::AUTHORIZATION_ENV_KEY)
      [200, {"x-subject" => result.claims.subject}, ["ok"]]
    end
    middleware = described_class.new(app, resource_server: allowed_server, scopes: ["memory.read"])

    status, headers, body = middleware.call("HTTP_AUTHORIZATION" => "Bearer token-1")

    expect(status).to eq(200)
    expect(headers).to include("x-subject" => "user-1")
    expect(body).to eq(["ok"])
  end

  it "returns the resource-server challenge for denied requests" do
    middleware = described_class.new(->(_env) { [200, {}, ["ok"]] }, resource_server: denied_server)

    status, headers, body = middleware.call({})

    expect(status).to eq(401)
    expect(headers.fetch("WWW-Authenticate")).to include("resource_metadata=")
    expect(body).to eq([])
  end

  it "computes scopes from the Rack env when scopes are callable" do
    app = ->(_env) { [200, {}, ["ok"]] }
    resource_server = instance_double(OAuth2::MCP::ResourceServer)
    allow(resource_server).to receive(:authorize).and_return(
      OAuth2::MCP::AuthorizationResult.allow(claims: OAuth2::MCP::TokenClaims.new),
    )
    middleware = described_class.new(app, resource_server: resource_server, scopes: ->(env) { [env.fetch("scope")] })

    middleware.call("scope" => "memory.read")

    expect(resource_server).to have_received(:authorize).with(
      request: hash_including("scope" => "memory.read"),
      scopes: ["memory.read"],
    )
  end

  def allowed_server
    result = OAuth2::MCP::AuthorizationResult.allow(
      claims: OAuth2::MCP::TokenClaims.new(subject: "user-1"),
    )
    instance_double(OAuth2::MCP::ResourceServer, authorize: result)
  end

  def denied_server
    challenge = OAuth2::MCP::BearerChallenge.new(resource_metadata: "https://brain.example.com/metadata")
    result = OAuth2::MCP::AuthorizationResult.deny(
      status: 401,
      error: nil,
      error_description: nil,
      required_scopes: [],
      challenge: challenge,
    )
    instance_double(OAuth2::MCP::ResourceServer, authorize: result)
  end
end

RSpec.describe OAuth2::MCP::ResourceServer do # rubocop:disable Metrics/BlockLength
  let(:metadata) do
    OAuth2::MCP::ProtectedResourceMetadata.new(
      resource: "https://brain.example.com/mcp",
      authorization_servers: ["https://auth.example.com"],
      scopes_supported: %w[memory.read memory.write],
    )
  end

  let(:metadata_url) { "https://brain.example.com/.well-known/oauth-protected-resource/mcp" }

  it "does not emit challenge headers for allowed results" do
    result = OAuth2::MCP::AuthorizationResult.allow(
      claims: OAuth2::MCP::TokenClaims.new(subject: "user-1"),
    )

    expect(result.headers).to eq({})
  end

  it "allows requests with a valid token, matching audience, and required scopes" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(scopes: %w[memory.read], audience: ["https://brain.example.com/mcp"]),
      scope_mapper: OAuth2::MCP::ScopeMapper.new(mapping: {"memory.read" => "documents_read"}),
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.read"],
    )

    expect(result).to be_allowed
    expect(result.claims.subject).to eq("user-1")
    expect(result.capabilities).to eq(["documents_read"])
  end

  it "returns a bearer challenge when the token is missing" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(scopes: %w[memory.read], audience: ["https://brain.example.com/mcp"]),
    )

    result = server.authorize(request: {headers: {}}, scopes: ["memory.read"])

    expect(result).not_to be_allowed
    expect(result.status).to eq(401)
    expect(result.headers.fetch("WWW-Authenticate")).to eq(
      'Bearer resource_metadata="https://brain.example.com/.well-known/oauth-protected-resource/mcp", ' \
        'scope="memory.read"',
    )
  end

  it "rejects tokens whose audience does not include the MCP resource" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(scopes: %w[memory.read], audience: ["https://other.example.com/mcp"]),
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.read"],
    )

    expect(result).not_to be_allowed
    expect(result.status).to eq(401)
    expect(result.error).to eq("invalid_token")
  end

  it "rejects tokens without the required scope" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(scopes: %w[memory.read], audience: ["https://brain.example.com/mcp"]),
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.write"],
    )

    expect(result).not_to be_allowed
    expect(result.status).to eq(403)
    expect(result.error).to eq("insufficient_scope")
  end

  it "rejects expired tokens" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(
        scopes: %w[memory.read],
        audience: ["https://brain.example.com/mcp"],
        expires_at: Time.now.to_i - 1,
      ),
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.read"],
    )

    expect(result).not_to be_allowed
    expect(result.error_description).to eq("Token is expired.")
  end

  it "allows tokens without resource audience when audience enforcement is disabled" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: validator(scopes: %w[memory.read], audience: ["https://other.example.com/mcp"]),
      require_resource_audience: false,
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.read"],
    )

    expect(result).to be_allowed
    expect(result.capabilities).to eq([])
  end

  it "normalizes hash claims returned by validate-style validators" do
    raw_validator = Class.new do
      def validate(_token)
        {
          "sub" => "user-1",
          "scope" => "memory.read",
          "aud" => "https://brain.example.com/mcp",
        }
      end
    end.new
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: raw_validator,
    )

    result = server.authorize(
      request: {headers: {"Authorization" => "Bearer token-1"}},
      scopes: ["memory.read"],
    )

    expect(result).to be_allowed
    expect(result.claims.subject).to eq("user-1")
  end

  it "rejects validators that return no claims" do
    server = described_class.new(
      resource_metadata: metadata,
      resource_metadata_url: metadata_url,
      validator: ->(_token) {},
    )

    result = server.authorize(request: {headers: {"Authorization" => "Bearer token-1"}})

    expect(result).not_to be_allowed
    expect(result.error_description).to eq("Token validator returned no claims.")
  end

  def validator(scopes:, audience:, expires_at: nil)
    lambda do |_token|
      OAuth2::MCP::TokenClaims.new(
        subject: "user-1",
        scopes: scopes,
        audience: audience,
        expires_at: expires_at,
      )
    end
  end
end
