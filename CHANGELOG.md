# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.6.1] - 2026-08-20

### Added
- `RecordingStudioAccessible.bootstrap_owner_access!` and
  `Services::BootstrapOwnerAccess` for the first `:admin` grant on an empty
  owned root recording, using the same Access write path as `grant_access`.
- Shared grant writer (`Services::AccessGrantWriter`) shared by grant and
  bootstrap so bootstrap cannot invent a parallel Access creation path.
- `SharedRootAccess.target?` also consults `RecordingStudio.shared_root_type?`
  when available, so shared-root grant surfaces fail closed consistently.

### Changed
- Dummy seeds bootstrap owned demo roots with `bootstrap_owner_access!` and
  create further demo grants through `grant_access` instead of
  `AccessCreationContext.allow`.
- Dummy `access_actor_types` include `Workspace` so seed through-actor grants
  stay on the supported grant path.

### Fixed
- `ensure_current_impersonator_accessor!` now uses `method_defined?` and clears
  stale same-named `CurrentAttributes` instances after `Current` is replaced,
  so grant/bootstrap/integrity writes do not call a missing `impersonator`
  method.

### Upgrade Notes
- Replace demo ENV authorizer patterns and host-facing
  `AccessCreationContext.allow` first-owner setup with
  `RecordingStudioAccessible.bootstrap_owner_access!(recording:, actor:)`.
- Call bootstrap only on owned roots (`shared: false`). Shared roots remain
  rejected; put grants on descendants beneath the shared root.
- After a successful bootstrap, continue using `grant_access` for invites and
  membership. The default `access_management_authorizer` is unchanged.
- Intended consumers: host apps and `recording_studio_users` create-first-root.
  Root Switchable should select the bootstrapped root afterward.

## [0.6.0] - 2026-08-20

### Added
- Shared-root access rules for RecordingStudio core 4.1: refuse new or updated direct grants on shared roots, keep revoke available for legacy grants, and hide mounted access management on shared roots.
- `RecordingStudioAccessible::SharedRootAccess` helper and `Compatibility.access_management_allowed?` for shared-root-aware access-management checks.
- `root_recordings_for` and `root_recording_ids_for` now exclude shared roots from actor-owned bucket lists while descendant authorization continues to work.

### Changed
- **Breaking dependency floor:** requires RecordingStudio `~> 4.1` (tested against `4.1.0`).
- Dummy app pins RecordingStudio `v4.1.0` and RecordingStudioRootSwitchable `v0.4.0`.
- Dummy `MessageRoot` is now a shared root without `:accessible`; `MessageGroup` remains the accessible host type under it.
- Dummy Tailwind now scans Bundler gem paths (including rbenv installs) and pins Turbo so FlatPack layout, buttons, and sidebar controllers load.

### Upgrade Notes
- Upgrade RecordingStudio to `4.1.0` or newer before installing Accessible `0.6.0`.
- Declare shared roots with `shared: true` on root recordables, but do **not** enable `:accessible` on shared root types. Enable `:accessible` on domain children beneath the shared root instead.
- New grants and updates on shared roots fail with: "Grant access on objects below a shared root, not on the shared root itself." Revoke legacy shared-root grants if needed.
- `root_recordings_for` / `root_recording_ids_for` no longer return shared roots. Use descendant grants or product-specific listing when you need shared-root context.

## [0.5.1] - 2026-08-16

### Changed
- Development and dummy-app bundles now track RecordingStudio `3.0.3` and Rails `8.1.3.1`.
- Dummy app pins FlatPack `v0.1.129` (ViewComponent 4) and RecordingStudioRootSwitchable `v0.3.5` instead of floating GitHub `main` / older tags.
- Aligned the dummy Tailwind `@source` paths and FlatPack theme tokens with RecordingStudio 3.0.3 so FlatPack 0.1.129 component classes are included in the build.
- Aligned public gem lockfiles between the engine and dummy app for Devise, PostgreSQL, Tailwind, RuboCop, Turbo, Solid Queue, and related compatible updates. Puma 8, Solid Cable 4, SimpleCov 1, Brakeman 8, image_processing 2, and RecordingStudio 4.0 are intentionally deferred.
- Added `minitest-mock` for the engine test suite so Minitest 6 (pulled in by Rails 8.1.3.1) still supports the existing `Object#stub` helpers.

### Upgrade Notes
- Hosts already on RecordingStudio `~> 3.0` can keep that constraint. This release is tested against `3.0.3`.
- RecordingStudio `4.0.0` is not supported yet. `recording_studio_root_switchable` 0.3.5 still requires RecordingStudio `~> 3.0`.
- Dummy-app hosts that copy this Gemfile should pin FlatPack to a release tag. `v0.1.129` is a ViewComponent 4 upgrade from the previous `0.1.33` lock.

## [0.5.0] - 2026-08-12

### Changed
- Breaking: new polymorphic access grants now fail closed when `config.access_actor_types` is blank or `nil`. Configure an explicit allowlist such as `["User", "Workspace"]`, or opt in to arbitrary persisted actor types with the security-sensitive exact symbol `:all`. Existing grants continue to authorize and can still be updated or revoked.

### Fixed
- Effective hierarchy access resolution now selects the strongest valid role granted on the target recording or an applicable ancestor. Actors with weaker descendant grants and stronger ancestor grants may receive broader authorization results.
- Same-parent malformed direct-access duplicates now resolve deterministically to their strongest valid role, independent of row order.

### Added
- Added the dry-run-by-default `recording_studio_accessible:access_grants:integrity` task and lifecycle-backed repair service for inspecting and repairing malformed active duplicate grants without schema or RecordingStudio recording/recordable architecture changes.

### Upgrade Notes
- Before deploying, configure `config.access_actor_types` with the persisted polymorphic types that may receive new grants. A blank or `nil` value now rejects every new grant; use `:all` only when arbitrary persisted actor types are intentional.
- Audit authorization flows that treated a weaker direct descendant grant as a restriction. The effective role now uses the strongest valid grant on the target recording or any applicable ancestor.
- Run `bin/rails recording_studio_accessible:access_grants:integrity` before deployment to report malformed same-parent duplicates. Repair only after reviewing the report with `DRY_RUN=false` and a persisted manager actor GlobalID; no database migration is required.

## [0.4.1] - 2026-07-02

### Added
- Added `ActionRegistry` for centralized action authorization: host apps can register named actions with metadata and define authorization policies via `RecordingStudioAccessible.register_action` and `RecordingStudioAccessible.define_action`
- Added `CheckRegistry` for reusable authorization predicates: host apps can define named checks via `RecordingStudioAccessible.define_check` and evaluate them with `RecordingStudioAccessible.check`
- Added `RegistryClassMethods` module providing the full registry API surface: `registered_actions`, `registered_action?`, `action_registration_for`, `defined_actions`, `action_policies`, `action_defined?`, `defined_checks`, `check_defined?`
- Added `authorized_action?` as a first-class query method that delegates through the action registry to evaluate registered action policies
- Added `Configuration#register_action` and `Configuration#authorized_action?` convenience delegates for host app initializer usage
- Added comprehensive regression coverage for action registration, definition, authorization, metadata introspection, and deep-frozen immutable registries

### Changed
- Action definitions are deep-frozen after registration to prevent accidental mutation of policy procs and metadata
- Registry introspection methods are hardened with exhaustive coverage for edge cases around missing, unregistered, and undefined actions and checks

### Fixed
- Resolved RuboCop lint issues in registry source files

## [0.4.0] - 2026-07-01

### Added
- Added `RecordingStudioAccessible.authorized_through?` and `RecordingStudioAccessible.role_through` for explicit through-actor authorization checks
- Added `config.authorize_actor_through` so host apps can define when one actor may use another actor's direct access grants
- Added configurable access-actor allowlisting through `config.access_actor_types` to constrain which polymorphic actor types may receive new grants
- Added navigation URL sanitization for mounted access-management flows to reject unsafe redirect and anchor targets

### Changed
- `RecordingStudioAccessible.grant_access` now rejects disallowed actor types before creating or revising direct access grants
- Access lifecycle services now resolve the acting manager through the configured current-actor resolver when `manager_actor` is omitted
- The mounted workspace actor access-point page now authorizes against access-management policy and the resolved actor instead of relying on the broader mounted-page authorization
- Updated generator templates, README guidance, and the dummy app to document through-actor access, actor allowlisting, and mounted access-management behavior

### Fixed
- Hardened mounted actor access-point lookups to validate UUID and actor-type params and fail closed on malformed or unauthorized requests
- Hardened mounted access-management redirects by filtering unsafe `back_url` and `anchor_url` values
- Expanded regression coverage for through-actor authorization, actor access-point authorization, and manager-actor attribution during grant flows

## [0.3.2] - 2026-06-17

### Added
- Added configurable access avatar helper support through `RecordingStudioAccessible.configuration`
- Added generator support for initializer defaults used by access avatar helper configuration

### Changed
- Refined access avatar helper rendering to behave consistently with and without FlatPack availability
- Updated README guidance for configuring and using access avatar helpers

### Fixed
- Hardened avatar helper guard behavior to avoid runtime issues when FlatPack components are unavailable
- Expanded regression coverage for avatar helper and configuration behavior
- Hardened access grant validation to block duplicate active direct access recordings for the same actor under the same parent recording
- `RecordingStudioAccessible.grant_access` now consistently deduplicates pre-existing duplicate direct grants within the same parent scope before updating role state

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.1...v0.3.1
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.1.0...v0.2.0
