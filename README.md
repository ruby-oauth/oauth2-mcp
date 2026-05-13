# oauth2-mcp

`oauth2-mcp` is a Ruby resource-server toolkit for securing HTTP Model Context
Protocol servers with OAuth 2.1-style bearer authorization.

It builds on the `oauth2` gem for the Ruby OAuth/OIDC substrate and adds the MCP
resource-server pieces that generic OAuth clients do not provide.

The gem is intentionally focused on the MCP server side:

- protected-resource metadata for MCP endpoint discovery;
- `WWW-Authenticate` bearer challenges;
- scope and capability mapping for application policy layers;
- provider adapters for WorkOS/AuthKit and generic OIDC/JWKS validation;
- explicit audience/resource validation so tokens cannot be replayed against
  another MCP server.

Token passthrough is not a supported pattern. MCP servers should validate the
incoming token for their own resource and issue separate downstream credentials
when calling other services. Successful authorization results expose normalized
claims and mapped capabilities, not the raw bearer token.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "oauth2-mcp"
```

Then run:

```bash
bundle install
```

## Usage

Build protected-resource metadata for an MCP endpoint:

```ruby
metadata = OAuth2::MCP::ProtectedResourceMetadata.new(
  resource: "https://brain.example.com/mcp",
  authorization_servers: ["https://example.authkit.app"],
  scopes_supported: %w[memory.read memory.write]
)

metadata.to_json
```

Return a bearer challenge when authorization is missing or insufficient:

```ruby
challenge = OAuth2::MCP::BearerChallenge.new(
  resource_metadata: "https://brain.example.com/.well-known/oauth-protected-resource/mcp",
  scope: %w[memory.read],
  error: "insufficient_scope",
  error_description: "memory.read is required"
)

headers["WWW-Authenticate"] = challenge.to_header
```

Authorize an MCP HTTP request with a provider-specific token validator:

```ruby
metadata = OAuth2::MCP::ProtectedResourceMetadata.new(
  resource: "https://brain.example.com/mcp",
  authorization_servers: ["https://example.authkit.app"],
  scopes_supported: %w[memory.read memory.write]
)

validator = OAuth2::MCP::JWTValidator.new(
  jwks: {"keys" => provider_jwks},
  issuer: "https://example.authkit.app",
  audience: "https://brain.example.com/mcp"
)

scope_mapper = OAuth2::MCP::ScopeMapper.new(
  mapping: {
    "memory.read" => "documents_read",
    "memory.write" => "documents_write"
  }
)

resource_server = OAuth2::MCP::ResourceServer.new(
  resource_metadata: metadata,
  resource_metadata_url: "https://brain.example.com/.well-known/oauth-protected-resource/mcp",
  validator: validator,
  scope_mapper: scope_mapper
)

result = resource_server.authorize(
  request: rack_env,
  scopes: ["memory.read"]
)

halt result.status, result.headers, "" unless result.allowed?
```

Protect a Rack-compatible MCP HTTP endpoint:

```ruby
use OAuth2::MCP::RackMiddleware,
  resource_server: resource_server,
  scopes: ["memory.read"]
```

Or build the validator from OIDC discovery:

```ruby
validator = OAuth2::MCP::OIDCDiscovery.new(
  issuer: "https://example.authkit.app"
).jwt_validator(
  audience: "https://brain.example.com/mcp"
)
```

For WorkOS AuthKit, use the provider adapter. It validates against the AuthKit
issuer and `/oauth2/jwks` endpoint:

```ruby
validator = OAuth2::MCP::WorkOSAuthKit.new(
  subdomain: "acme",
  audience: "https://brain.example.com/mcp"
)
```

For opaque access tokens, use OAuth token introspection with an `OAuth2::Client`
configured for the authorization server:

```ruby
validator = OAuth2::MCP::IntrospectionValidator.new(
  client: oauth_client,
  introspection_url: "https://auth.example.com/oauth2/introspection",
  audience: "https://brain.example.com/mcp",
  issuer: "https://auth.example.com"
)
```

## Roadmap

- MCP scope challenge helpers.

## Relationship to `oauth2`

The `oauth2` gem remains the core OAuth 2.0/2.1 and OIDC client/Relying Party
library. `oauth2-mcp` should not duplicate those flows. It should reuse `oauth2`
for client credentials, authorization code + PKCE, token refresh, provider HTTP
behavior, and shared OAuth vocabulary.

`oauth2-mcp` owns the MCP resource-server layer:

- protected-resource metadata;
- MCP-specific `WWW-Authenticate` challenges;
- bearer token extraction from MCP HTTP requests;
- token validation adapters for JWT/JWKS and introspection;
- resource/audience validation for MCP server URIs;
- scope-to-application-capability mapping;
- Rack/Roda middleware for MCP endpoints.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run:

```bash
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome at
https://github.com/ruby-oauth/oauth2-mcp.

## License

The gem is available as open source under the terms of the MIT License.
