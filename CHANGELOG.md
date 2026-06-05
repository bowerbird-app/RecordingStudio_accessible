# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.1] - 2026-06-05

### Changed
- Updated Recording Studio Accessible for RecordingStudio `3.0.0` capability-owned child recordables
- Replaced addon-maintained `RecordingStudio::Access` parent injection and placement policy with RecordingStudio core capability enablement and parent checks
- Removed the addon-owned `recording_studio_accessible_children` workaround in favor of direct `RecordingStudio.enable_capability(:accessible, on: ...)` usage

### Fixed
- Updated the dummy app, README, and regression coverage to follow the final RecordingStudio 3 capability API
- Removed stale generated dummy app artifacts that caused RuboCop failures during full validation

### Upgrade Notes
- Breaking: host apps must use RecordingStudio `~> 3.0`
- `RecordingStudio::Access` remains child-only, but its effective parents now come from enabling the `:accessible` capability with `RecordingStudio.enable_capability(:accessible, on: YourRecordable)`
- Remove any `include RecordingStudioAccessible::AllowsAccessibleChildren` or `recording_studio_accessible_children :access` usage from host apps and replace it with direct RecordingStudio capability enablement
- Continue creating direct grants through `RecordingStudioAccessible.grant_access`; direct `RecordingStudio::Access` creation remains unsupported

## [0.2.1] - 2026-06-03

### Added
- `allow_accessible_children` declarations for hierarchy-aware recordables and matching dummy app coverage
- Focused regression coverage for placement policy, migration generation, access helpers, and RecordingStudio 2 access flows

### Changed
- Updated the `recording_studio` dependency target and compatibility layer for the RecordingStudio 2 follow-up release
- Refined direct-access queries, authorization helpers, and access record lifecycle handling for nested accessible content
- Refreshed the dummy app seeds and installation guidance to match the current RecordingStudio 2 setup

### Fixed
- `rake app:test` now runs the dummy app suite with the dummy app's Bundler context
- Removed redundant standard-library requires flagged by RuboCop

### Upgrade Notes
- If a host app expects child recordings to participate in access lookups, declare those relationships with `allow_accessible_children`

## [0.2.0] - 2026-06-03

### Added
- Initial extraction scaffold for Recording Studio Accessible
- Compatibility-aware access loading, generators, and dummy app demo

### Changed
- Direct creation of `RecordingStudio::Access` and direct access recordings is blocked when this addon is loaded
- The creation guards also apply in compatibility mode when RecordingStudio core still provides `RecordingStudio::Access`
- Host applications must use `RecordingStudioAccessible.grant_access` for new direct grants

### Upgrade Notes
- Replace any `RecordingStudio::Access.create!` plus `RecordingStudio::Recording.unscoped.create!` flow with `RecordingStudioAccessible.grant_access`
- Replace any `parent_recording.record(RecordingStudio::Access, ...)` usage with `RecordingStudioAccessible.grant_access`
- The supported service path centralizes placement checks, authorization, role validation, and duplicate direct-grant cleanup

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.1...v0.3.1
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.1.0...v0.2.0
