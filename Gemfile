# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in oauth2-mcp.gemspec
gemspec

oauth2_path = File.expand_path("../oauth2", __dir__)
gem "oauth2", path: oauth2_path if File.directory?(oauth2_path)

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
