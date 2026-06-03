# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.1.0...v0.2.0
