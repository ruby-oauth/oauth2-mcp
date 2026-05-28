# frozen_string_literal: true

# kettle-jem:freeze
# To retain chunks of comments & code during oauth2-mcp templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# oauth2-mcp will then preserve content between those markers across template runs.
# kettle-jem:unfreeze

source "https://gem.coop"

#### IMPORTANT #######################################################
# Gemfile is for local development ONLY; Gemfile is NOT loaded in CI #
####################################################### IMPORTANT ####

# Include dependencies from oauth2-mcp.gemspec
gemspec

oauth2_path = File.expand_path("../oauth2", __dir__)
gem "oauth2", path: oauth2_path if File.directory?(oauth2_path)

# See unlocked_deps appraisal for more details on irb inclusion
gem "irb", "~> 1.17" # ruby >= 2.7
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"

git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }

git_source(:gitlab) { |repo_name| "https://gitlab.com/#{repo_name}" }

# Templating (env-switched: SMORG_RB_DEV=/path/to/structuredmerge/ruby/gems for local paths)
eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

# Debugging
eval_gemfile "gemfiles/modular/debug.gemfile"

# Code Coverage (env-switched: KETTLE_RB_DEV=true for local paths)
eval_gemfile "gemfiles/modular/coverage.gemfile"

# Linting
eval_gemfile "gemfiles/modular/style.gemfile"

# Documentation
eval_gemfile "gemfiles/modular/documentation.gemfile"

# Optional
eval_gemfile "gemfiles/modular/optional.gemfile"

### Std Lib Extracted Gems
eval_gemfile "gemfiles/modular/x_std_libs.gemfile"
