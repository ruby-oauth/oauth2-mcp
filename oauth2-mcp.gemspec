# frozen_string_literal: true

require_relative "lib/oauth2/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "oauth2-mcp"
  spec.version = OAuth2::MCP::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["peter.boling@gmail.com"]

  spec.summary = "OAuth 2.1 resource-server helpers for MCP servers."
  spec.description = "oauth2-mcp provides Ruby helpers for securing HTTP Model Context Protocol servers " \
                     "with OAuth protected-resource metadata, bearer challenges, and scoped authorization."
  spec.homepage = "https://github.com/ruby-oauth/oauth2-mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ruby-oauth/oauth2-mcp"
  spec.metadata["changelog_uri"] = "https://github.com/ruby-oauth/oauth2-mcp/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "jwt", ">= 2.7", "< 4.0"
  spec.add_dependency "oauth2", ">= 2.0", "< 3.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
