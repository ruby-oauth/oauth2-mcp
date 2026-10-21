# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- kettle-jem-template-20260720-005 - README Support & Community links now
  include RubyForum.
- kettle-jem-template-20260726-001 - Projects now include YARD lint
  configuration and documentation dependencies so documentation issues fail
  before generated docs are refreshed.
- kettle-jem-template-20260727-001 - Spec harness documentation now lists the
  RSpec helpers provided by `kettle-test`.

- kettle-jem-template-20260913-001 - Templating now also surfaces a review
  entry in `dependency_conflicts.resolve` when a direct development
  dependency doesn't support one or more of this project's declared
  `engines:` and has no template-managed modular home (e.g. `sqlite3` on
  `jruby`). Review each entry and pick a resolution per the project's own
  engine support needs.

### Changed

- kettle-jem-template-20260716-002 - Generated gemspec manifests now ship fewer
  repository-only files by default to reduce downstream distro packaging churn.

- kettle-jem-template-20260720-002 - Development Gemfiles now use the released
  `tree_sitter_language_pack` gem 1.13.3 or newer by default.
- kettle-jem-template-20260725-002 - Version specs now use `anonymous_loader` to
  cover `version.rb` without redefining constants, or are removed when version
  specs are not managed for the project.
- kettle-jem-template-20260728-001 - Generated Ruby workflows now use clearer
  setup-ruby-flash planning and can prepare appraisal-only jobs without
  installing the main Gemfile bundle.

- kettle-jem-template-20260801-001 - Generated README gem dashboard links now
  use ClickGems instead of BestGems.

- [kc] kettle-jem/prepare: updated 17 project files:
  - configuration (1)
  - dependencies (16)

- [kc] kettle-jem/template: updated 37 project files:
  - code and tests (3)
  - configuration (1)
  - dependencies (7)
  - documentation (2)
  - other (5)
  - workflows (19)

### Deprecated

### Removed

### Fixed

- kettle-jem-template-20260720-003 - StructuredMerge Git diff driver config now
  uses the installed `smorg-rb` driver command.
- kettle-jem-template-20260725-001 - Release pull request branches beginning
  with `feature/release` now run JRuby and TruffleRuby workflows.
- kettle-jem-template-20260726-002 - Generated version files now document their
  version namespace and constants, reducing warning-only YARD lint output.
- kettle-jem-template-20260726-003 - Coverage upload steps now treat Coveralls,
  QLTY, and Codecov as optional, so provider outages do not fail CI when local
  coverage thresholds still pass.
- kettle-jem-template-20260728-002 - Generated RuboCop configs now ignore the
  same `gemfiles/vendor/bundle` tree as `.gitignore`, so vendored dependency
  installs are not reported as project lint debt.
- kettle-jem-template-20260728-003 - Generated dep-heads workflows now run
  TruffleRuby jobs with current RubyGems and Bundler, avoiding setup failures
  before the test suite starts.
- kettle-jem-template-20260728-004 - Generated dep-heads workflows now use the
  setup-ruby Bundler install path for direct appraisal Gemfiles, avoiding rv
  lockfile parser failures on Git and path dependencies.
- kettle-jem-template-20260728-005 - VersionGem bootstrap now creates the
  missing canonical version spec when a project only has shim namespace version
  specs.
- kettle-jem-template-20260730-001 - Gemspec package file enumeration now runs
  relative to the gemspec directory, so release package contents stay correct
  even when the gemspec is loaded from another working directory.

- kettle-jem-template-20260801-002 - Generated RSpec helpers now normalize
  managed configuration block bindings structurally, preventing mixed block
  parameter names from producing invalid configuration after a merge.
- kettle-jem-template-20260801-003 - Generated project metadata and
  documentation now normalize configured underscore hostnames to valid
  hyphenated hostnames.
- kettle-jem-template-20260801-004 - Generated organization README logos now
  use GitHub's stable organization avatar endpoint instead of assuming a
  matching Galtzo-hosted asset exists.
- kettle-jem-template-20260802-001 - Devcontainer JSON files now merge as JSONC,
  preserving comments and trailing commas during template updates.

### Security

## [0.1.2] - 2026-07-14

- TAG: [v0.1.2][0.1.2t]
- COVERAGE: 100.00% -- 285/285 lines in 2 files
- BRANCH COVERAGE: 100.00% -- 82/82 branches in 2 files
- 67.05% documented

### Added

- Added support for JRuby 10.1 and TruffleRuby 34.0.

### Changed

- Retemplated generated project metadata, support documentation, CI workflows,
  binstubs, and development dependency floors with `kettle-jem` v7.0.0.

### Fixed

- Corrected RubyGems homepage metadata to point at the gem documentation site.
- Corrected persisted Open Collective metadata to use the `ruby-oauth`
  collective.

- Package configured license files in gem release file lists.

## [0.1.1] - 2026-06-15

- TAG: [v0.1.1][0.1.1t]
- COVERAGE: 100.00% -- 285/285 lines in 2 files
- BRANCH COVERAGE: 100.00% -- 82/82 branches in 2 files
- 67.05% documented

### Changed

- Refreshed generated package metadata, support documentation, CI workflows,
  `version_gem` >= 1.1.12, `appraisal2` >= 3.1.2, `nomono` >= 1.0.4, and
  development dependency floors from the current kettle-jem template.
- Updated generated OpenCollective funding metadata to use the
  `ruby-oauth` collective.
- Raised the runtime dependency floor for `oauth2` to `>= 2.0.23`.
- Updated the locked `auth-sanitizer` runtime dependency to v0.2.1.
- Updated the locked `snaky_hash` runtime dependency to v2.0.5.
- Updated generated documentation dependency metadata to require
  `yaml-converter` >= 0.2.1.

### Fixed

- Restored `docs/CNAME` so the generated documentation site keeps its custom domain.
- Fixed generated documentation URLs that incorrectly pointed at a monorepo
  `gems/oauth2-mcp` path.

## [0.1.0] - 2026-05-28

- TAG: [v0.1.0][0.1.0t]
- COVERAGE: 100.00% -- 285/285 lines in 2 files
- BRANCH COVERAGE: 100.00% -- 82/82 branches in 2 files
- 67.05% documented
- Initial release

### Fixed

- Treated unsupported OAuth introspection response shapes as inactive tokens
  instead of allowing low-level indexing errors to escape.

[Unreleased]: https://github.com/ruby-oauth/oauth2-mcp/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/ruby-oauth/oauth2-mcp/compare/v0.1.1...v0.1.2
[0.1.2t]: https://github.com/ruby-oauth/oauth2-mcp/releases/tag/v0.1.2
[0.1.1]: https://github.com/ruby-oauth/oauth2-mcp/compare/v0.1.0...v0.1.1
[0.1.1t]: https://github.com/ruby-oauth/oauth2-mcp/releases/tag/v0.1.1
[0.1.0]: https://github.com/ruby-oauth/oauth2-mcp/compare/03b55e60f4a464acdaa9ebd4e29556579055f102...v0.1.0
[0.1.0t]: https://github.com/ruby-oauth/oauth2-mcp/releases/tag/v0.1.0
