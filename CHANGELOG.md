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

### Changed

- Raised generated `version_gem` and `appraisal2` dependency floors to
  `version_gem` >= 1.1.10 and `appraisal2` >= 3.0.9.
- Refreshed generated package metadata, support documentation, CI workflows,
  and development dependency floors from the current kettle-jem template.
- Updated generated OpenCollective funding metadata to use the
  `ruby-oauth` collective.
- Updated the locked `auth-sanitizer` runtime dependency to v0.2.1.

### Deprecated

### Removed

### Fixed

- Fixed generated documentation URLs that incorrectly pointed at a monorepo
  `gems/oauth2-mcp` path.

### Security

## [0.1.0] - 2026-05-28

- TAG: [v0.1.0][0.1.0t]
- COVERAGE: 100.00% -- 285/285 lines in 2 files
- BRANCH COVERAGE: 100.00% -- 82/82 branches in 2 files
- 67.05% documented
- Initial release

### Fixed

- Treated unsupported OAuth introspection response shapes as inactive tokens
  instead of allowing low-level indexing errors to escape.

[Unreleased]: https://github.com/ruby-oauth/oauth2-mcp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ruby-oauth/oauth2-mcp/compare/03b55e60f4a464acdaa9ebd4e29556579055f102...v0.1.0
[0.1.0t]: https://github.com/ruby-oauth/oauth2-mcp/releases/tag/v0.1.0
