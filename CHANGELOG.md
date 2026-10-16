# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.20.0] - 2026-10-16

### Added
- `RecordingStudio::AccessRequest`, a child recordable of the target. Submit,
  re-submit, approve, deny, and withdraw each revise the snapshot and append
  an event, so who did it and when stay on the history.
- `RecordingStudioAccessible.request_access`, `approve_access_request`,
  `deny_access_request`, and `withdraw_access_request`. One open request per
  person and target. Approval revises the request and grants access in one
  transaction. Revoking the grant later leaves the request history alone.
- Visitor screens for email, code, the request, and the confirmation. Each
  works as a full page and inside a Flatpack modal. The email step shows the
  recording's name or title, asks for a name, and passes that name to
  `complete_email_proof!` when the account is created. The request form does
  not ask for a role. The manager chooses the role when approving. Visitor
  copy can be overridden per flow with `copy:` or an I18n scope.
- Optional pre-request gate, `register_access_request_gate`, keyed by the
  requested action or `:default` when there is no action. The step sits after
  the email code and before the note. `create` checks it again. Continuation
  URLs must stay on the same host. A raising gate shows an alert and does not
  record the request. Sanitized answers are stored as `gate_metadata` on the
  snapshot at submit and re-submit, and managers see them beside the note.
  The name is required only when the user model requires one. A signed-in
  person skips the email code. Visitors get an account through Recording
  Studio Users (`issue_otp!`, `verify_otp!`, `complete_email_proof!`). There
  is no guest path.
- `access_request_modal` for locked screens. Approval sends the existing
  access-granted email. Managers get `AccessRequestSubmittedMailer`. Hooks:
  `:access_request_submitted`, `:access_request_approved`, `:access_request_denied`.

### Upgrade notes
- Run `rails generate recording_studio_accessible:migrations` and migrate.
  New tables: `recording_studio_access_requests` and
  `recording_studio_access_request_intents`. `gate_metadata` is added to
  `recording_studio_access_requests`.
- Accessible does not depend on Users in the gemspec. Users already depends
  on Accessible, and a gemspec dependency would cycle. Hosts that want the
  email-code screens add `recording_studio_user` (with notifications and
  cache) the same way Messages does. Without it, `request_access` still works
  for an existing signed-in actor; the email step tells the visitor that
  codes are unavailable.

## [0.19.0] - 2026-10-14

### Added
- English fallback for shipped `recording_studio.accessible.*` keys when the
  active locale has no translation: `Copy.t` / `accessible_t` route through
  `RecordingStudio.t`, which resolves loaded `:en` (host English overrides
  included), then the caller's `default:`, then the merged shipped-English
  table. This gem registers `config/locales/en.yml` at boot via
  `RecordingStudio::Translation.register_shipped_english`.
- Behavioral coverage: a locale with no translations renders loaded English on
  manage access; a boot-loaded host English override for the rarely shown
  `manage.expired` label wins on a real page; keys deleted from the loaded
  backend still render this gem's English through `RecordingStudio.t` (not
  "Translation missing", not a 500) with raise-on-missing on and off; en.yml
  drift guard rejects hand-copied English `default:`s; registration of this
  gem's `en.yml` path is asserted.

### Changed
- Depends on `recording_studio ~> 4.7` for `register_shipped_english`.
- Gem call sites look up copy through `Copy.t` / `RecordingStudio.t` so
  fallback English comes from the loaded `:en` backend or the registered
  gem-shipped table (no hand-copied Ruby string defaults that can drift).
- Public message constants (`GRANT_DENIED_MESSAGE`, bootstrap messages,
  duplicate-grant errors, recordable `LABEL`s / `WRITE_ERROR` /
  `NAME_DEFAULT`) remain for API compatibility; displayed copy no longer
  passes them as `default:`.

### Upgrade notes
- Install Accessible `0.19.0` with RecordingStudio `~> 4.7`. No migration.
  English hosts need no change.
- Hosts that enable raise-on-missing translations no longer raise for
  gem-shipped `recording_studio.accessible.*` keys looked up through
  `RecordingStudio.t` / `Copy.t` / `accessible_t` when the active locale
  lacks the key. Host overrides in the active locale still win; host `:en`
  overrides win on the loaded-English fallback step.
- Partial pluralization in a non-English locale (for example French with only
  `one`) still raises `I18n::InvalidPluralizationData` — the English fallback
  does not fill missing plural keys.
- A missing `_html` key with a caller `default:` now follows
  `RecordingStudio.t` / view `t` escaping (args escaped, template markup
  kept) instead of main's `Copy.t` whole-template escaping. No in-gem call
  site does this.
- `en.yml` is unchanged. Prefer `RecordingStudio.t` / `Copy.t` for gem keys
  when adding new call sites so missing locales keep the same fallback.

## [0.18.1] - 2026-10-14

### Changed
- `ControllerAuth#authenticate_recording_studio_actor!` logs a `Rails.logger.warn` naming the configured `authentication_method` when that hook is not defined on the controller. The response stays `:unauthorized` (same outcome as before).

### Upgrade Notes
- Install Accessible `0.18.1`. No migration. No API change.

## [0.18.0] - 2026-10-13

### Added
- `RecordingStudioAccessible::ControllerAuth` concern for sibling Recording Studio addon engines: class macro `recording_studio_auth config:, prefix:` wires authenticate + `Current.actor` before_actions and defines private one-line helpers (`authenticate_<prefix>_actor!`, `<prefix>_actor`, `current_<prefix>_root` helper, `set_<prefix>_current_actor`) so Rails does not treat them as actions.
- Shared helpers: `authenticate_recording_studio_actor!`, `recording_studio_actor`, `authorize_recording!(recording, role:)`, `current_recording_studio_root`, and `require_root!`.
- Divergence options for sibling gems:
  - status codes, `:head` / `:plain` / callable `response_style`, `plain_bodies`
  - `set_current_actor`, `actor_resolution` (`:current_then_method`, `:method_then_current`, `:method_only`, `:configured_as_is`)
  - method-name overrides (`authenticate_method`, `actor_method`, `set_current_actor_method`, `root_method`) for site_settings-style names
  - `authenticate: false`, `require_actor`, `on_missing_actor_for_root`, `actor_resolver`, `root_resolver` for stripe-style flows
- Macro guards: prefix must match `/\A[a-z_][a-z0-9_]*\z/`, second call raises, options are frozen, class attributes are class-only readers.
- Dummy-app coverage for the macro, each shared method, `action_methods` exclusion, blank `Current.actor` via `.presence`, nil-recording authorize, actor_resolution validation, site_settings names, and stripe require-root flow.
- Documents that `authentication_method` is the approved exception to “sign-in belongs in Users”: Users already depends on Accessible for permissions, so Accessible cannot depend on Users; hosts point the hook at Devise (for example `authenticate_user!`).

### Upgrade Notes
- Install Accessible `0.18.0`. No migration.
- Addon engines may replace duplicated ApplicationController auth with:

```ruby
include RecordingStudioAccessible::ControllerAuth

recording_studio_auth(
  config: -> { RecordingStudioX.configuration },
  prefix: :x
)
```

- Pass options only when a gem’s previous status codes, method names, or response style differed from the presskits defaults (`head :unauthorized` / `head :forbidden`). Host overrides of the generated private helpers keep working.

## [0.17.0] - 2026-10-13

### Changed
- Soft-trash predicates in dependent-access effectiveness and access-record
  lifecycle call `recording_studio_trashable_kept?` when present, otherwise
  fall back to `trashed_at.nil?` (same as main for duck-typed objects that
  expose `trashed_at` without Trashable helpers).
- Scope filters that were `where(trashed_at: nil)` now use additive
  `where(recording_studio_trashable_kept_sql)` (byte-equivalent kept filter).
  They do **not** call `recording_studio_trashable_active`, which
  `unscope(where: :trashed_at)` first and can diverge under a host
  `default_scope` that already constrains `trashed_at`.
- Depends on `recording_studio_trashable ~> 0.10` via
  `require "recording_studio_trashable/query"` only (Gemfile pin: git tag
  `v0.10.0`, `require: false`). Does not load the Trashable Rails engine,
  importmap/assets, `:trashable` capability, CopyHelper, or trash metrics.

### Upgrade Notes
- Install Accessible `0.17.0` and resolve `recording_studio_trashable` `~> 0.10`
  (git tag `v0.10.0` or equivalent). Prefer `require: false` plus Accessible’s
  query require; hosts that want Trashable UI still load the full engine
  themselves.
- No Accessible migration. Hosts that already have `trashed_at` keep the same
  active-row filtering; column-existence / `respond_to?(:trashed_at)` guards
  remain so boots without the column still work.
- Revoke / dependent void still hard-destroy Access recordings
  (`destroy!`). Accessible does not call `RecordingStudioTrashable.void_recording!`
  (that API is for soft-void writers such as Oauth).
- Partial-index `WHERE` clauses stay unqualified `trashed_at IS NULL` per
  Trashable guidance.
- Version is `0.17.0` (not `0.16.0`) so it does not collide with the open
  ControllerAuth PR `#34`, which reserves `0.16.0`.

## [0.15.0] - 2026-10-12

### Added
- English Rails I18n keys for HomeController demo method/invite copy, call-time recordable labels, and remaining user-facing service/validation errors under `recording_studio.accessible.*`.
- Host English override coverage: test-only fixture `test/dummy/test/locales/accessible_host_override.en.yml` plus an integration test that appends that file last to `I18n.load_path`, calls `I18n.backend.load_translations` on it, asserts a nested key wins on a real manage-access page, then restores the load path and a deep snapshot of the I18n backend (no bare `I18n.reload!`).
- Locale regression: every `lib/**/*.rb` file must not mention `i18n.load_path` / `I18n.load_path`. Unit tests seed gem English via `I18n.backend.store_translations` instead of appending the locale file to the load path.
- Rendered-page asserts cover engine home snapshot labels (methods, user invites, email preview).

### Changed
- Creation-guard and bootstrap/integrity failures resolve through `Copy.t(..., default: <constant English>)` while public message constants stay for API compatibility.
- Validation `errors.add` for former English-string types passes `Copy.t(..., default: <main's English>)` as the String type (ActiveModel 8.1 ignores `message:` for Strings); symbol-typed invitation errors keep `errors.add(attr, :sym, message: ...)`. In non-English locales, `errors.details` carries the translated string for those former String types.
- Recordable `recordable_type_label` / `recordable_name` / `audience_write_error` resolve at call time; `recording_studio_recordable label:` stays English (class-load DSL).
- Layout title / `application-name` meta pass an English `default:` so non-HTML surfaces never emit “Translation missing”.

### Upgrade Notes
- Install Accessible `0.15.0`. No migration.
- English hosts need no change. Copy new `recording_studio.accessible.home.methods.*`, `home.user_invites.statuses.*`, `home.user_invites.setup.*`, `recordables.*`, and `errors.*` keys into host locale files when translating.
- Hosts override by defining the same nested keys in their own `config/locales`. Public constants (`GRANT_DENIED_MESSAGE`, bootstrap messages, duplicate-grant errors, recordable `LABEL`s) remain; displayed copy follows the locale with those constants as `default:`.

## [0.14.0] - 2026-10-10

### Added
- Registrable action audiences (`public`, `signed_in`, `granted`, plus `register_audience`) and per-action host config `config.action_audiences`.
- `RecordingStudio::AccessConstraint` (workspace limit) and `RecordingStudio::AccessRule` (per-recording audience), with history, trash, and at most one live row per action per recording.
- Public API: `effective_audience`, `audience_options_for`, `set_audience!`, `set_audience_constraint!`, `granted_roles_for`.
- Persistent fallback: narrowing a workspace rewrites now-disallowed descendant rules to `granted` with an `audience_fallback` event. Relaxing never restores the old audience.
- `:action_audiences` capability so hosts opt types in independently of `:accessible`.

### Changed
- `authorized_action?` uses audience resolution for actions listed in `action_audiences` (audience predicate, or granted when `granted_override` is on). Unconfigured actions keep their existing policies.
- `register_audience` raises if the name is a built-in (`public`, `signed_in`, `granted`) or the internal `denied` sentinel.
- `set_audience!` locks the workspace root (then the target recording) and re-checks the allowed set inside the transaction so a concurrent workspace limit cannot leave a now-disallowed audience stored.
- Fallback events include the rule revision id in their idempotency key.
- Boot logs a warning when `config.action_audiences` takes over an action that already has a host `define_action` policy.

### Upgrade Notes
- Install Accessible `0.14.0`, then run:

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

- Existing apps do nothing until they set `config.action_audiences` and enable `:action_audiences` on the types that should hold rules and workspace limits.
- Copy `recording_studio.accessible.audiences.*` into host locale files when translating picker labels.
- `granted` stays in every allowed set. An action with no valid `granted_roles` is denied.
- Narrowing host `config.action_audiences` does not rewrite stored rules; only `set_audience_constraint!` persists fallback.
- No audience UI ships here. Host screens should use `audience_options_for` with Flatpack `RadioGroup`. Staff limits belong in Recording Studio Admin.

## [0.13.0] - 2026-10-09

### Added
- English Rails I18n keys for remaining gem views: actor access points and engine demo/docs home pages (`home.*`, `actor_access_points.*` under `recording_studio.accessible`).

### Changed
- Actor access points and engine home demo screens resolve static interface copy through `accessible_t` / `Copy.t` (English output unchanged).
- Actor access point role cells use `accessible_role_name` so role labels follow `recording_studio.accessible.roles.*`.
- `Copy.role_name` returns an empty string for nil or blank roles instead of looking up the roles hash.

### Upgrade Notes
- Install Accessible `0.13.0`. No migration.
- English hosts need no change. To translate the new screens, copy `recording_studio.accessible.actor_access_points.*` and `recording_studio.accessible.home.*` into host locale files.
- Engine demo/docs home copy is now overridable; controller-supplied method and invite-status examples stay English developer content.

## [0.12.0] - 2026-10-08

### Added
- Customer invitation, mail, and manage-access copy uses Rails I18n under `recording_studio.accessible.*`. The gem ships English only in `config/locales/en.yml`.
- `config.access_notification_locale` lets the host pick the locale for invitation and access-granted mail. Default is the current locale. No new database column.

### Changed
- Dummy pins FlatPack `v0.1.208` and adds Recording Studio Internationalization (dummy only) with a French locale file covering every engine key.

### Upgrade Notes
- Install Accessible `0.12.0`. No migration.
- Copy `recording_studio.accessible.*` into host locale files for other languages.
- Config callables for subjects, actor labels, and missing-actor errors still win over locale defaults.
- Role labels look up `recording_studio.accessible.roles.<name>` and fall back to humanize for custom host roles.
- Invitation and access-granted mail render inside `I18n.with_locale`. Override with `access_notification_locale` when the host already knows the recipient's language.

## [0.11.2] - 2026-10-06

### Changed
- Dummy credentials use the shared Recording Studio development master key. `RAILS_MASTER_KEY` writes gitignored `test/dummy/config/master.key`.

## [0.11.1] - 2026-10-02

### Changed
- Development and dummy companion pin for RecordingStudio moved from git tag `v4.2.0` to `v4.2.2` (gem version `4.2.1`).

## [0.11.0] - 2026-10-02

### Added
- `accessible_roles` declares the direct role names for one recordable class. A class with no declaration still uses `view`, `edit`, and `admin`.
- `RecordingStudioAccessible.authorized_for_any_role?` walks the existing access path and returns true when the actor has any listed role.
- `RecordingStudioAccessible.authorized_for_role?` matches one exact role name on that same path.
- `RecordingStudioAccessible.roles_for` and `role_valid_for?` read the role names for a recording.

### Changed
- `recording_studio_accesses.role` stores the role name as a string. The migration converts `0`, `1`, and `2` to `view`, `edit`, and `admin` only after it checks that no other integer is stored.
- Grant, update, and invitation writes accept a role only when the target context declares it. Authorization matching does not reject an ancestor role for being outside the target context's list.
- Manage access role choices come from the target context. Labels are the humanized role names.
- A dependent grant whose role, or whose manager role, is outside `view`, `edit`, and `admin` fails with "Dependent access requires a ranked role". Ranked dependent grants stay on the existing cap.

### Upgrade Notes
- Install Accessible `0.11.0`, then run:

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

- No model changes are required. Existing `authorized?` checks keep the `view < edit < admin` hierarchy.
- `RecordingStudio::AccessRoles::ORDER` is unchanged and is not a host setting.
- A context that omits `admin` cannot use `bootstrap_owner_access!`, because that command still grants `admin`.
- Dependent grants still require a ranked role on both sides. Custom names stay on independent grants and on `authorized_for_role?` / `authorized_for_any_role?`.
- Rollback of the role-column migration is allowed only while every role is `view`, `edit`, or `admin`. A custom role name stops the rollback so it is not rewritten.

## [0.10.1] - 2026-10-01

### Fixed
- Manage access "People with access" rows render inside the table columns. Grant and invitation cells were written into the row before the cells, so the browser lifted them out of the table.

### Changed
- The dummy Tailwind entry no longer redeclares FlatPack color or radius tokens. `data-theme="rounded"` is the theme that shows.

### Upgrade Notes
- Install Accessible `0.10.1`. No migration.
- Hosts that copied the old dummy Tailwind token block (`--color-primary`, `--radius-md`, and the related `--color-fp-*` names) into their own stylesheet should remove it so `data-theme="rounded"` can apply.

## [0.10.0] - 2026-10-01

### Added
- Pending access invitations. `AccessInvitation` stores intent for an email that does not yet belong to an actor. `RecordingStudio::Access` remains the only authorization record.
- `RecordingStudioAccessible.invite_access`, `accept_access_invitation`, and `revoke_access_invitation`.
- `AccessInvitationMailer`, plus engine routes to show, accept, resend, and cancel an invitation.

### Changed
- An unknown email in the mounted access-management flow now creates a pending invitation. The default missing-actor handler used to return a not-found error for that email.
- `invite_access` returns success only after the configured invitation notifier hands the message off. A failed notification leaves the invitation row in place and returns an error. A later invite or resend can retry delivery. A failed resend does not replace a token that was already delivered. The new token, role, manager, expiry, and last sent time are stored only after the replacement handoff succeeds.
- Invitations do not authorize anyone until accepted. `authorized?` and `role_for` ignore them.

### Upgrade Notes
- Install Accessible `0.10.0`, then run:

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

- To keep the previous unknown-email behavior, return `MissingActorResolution.invalid(...)` from the missing-actor handler.
- A custom `access_invitation_notifier` reports success with a truthy handoff, such as the delivered mail. Return `false`, `nil`, or an object whose `success?` is false to report failure. A raised error is also failure. The default notifier fails when it cannot build an acceptance URL, and it does not send that mail.

## [0.9.1] - 2026-09-02

Cloud Agent Builds for this gem now match Billing 0.9.13. Boot files are
tracked. A warm snapshot skips provision and still fetches skills.

### Added
- `.cursor/fetch-skills.sh`, `.cursor/install.sh`, `.cursor/start.sh`, and
  `.cursor/environment.json` for Cloud Agent boot. Install skips apt,
  ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
  already usable. A skippable provision failure does not fail the Build.
  Fetch-skills always runs last. Start only brings PostgreSQL up.

### Upgrade Notes
- No host or schema changes. Rebuild the Cloud Agent environment with Draft
  off so Build loads the pack.

## [0.9.0] - 2026-09-01

### Added
- Dependent grants now void when the manager Access recording is moved.
  Dependents stay at the old node and are destroyed; they do not follow the
  manager to the new parent. Moveable's `move_to!` updates
  `parent_recording_id` (and `root_recording_id` on a cross-root transfer);
  Accessible hooks that Recording lifecycle instead of adding a second ACL.

### Changed
- `VoidDependentAccesses` / `VoidDependentAccessesJob` accept `moved: true`
  so a manager move voids dependents even when they would still look
  same-root/role-capped until the grant is gone.

### Upgrade Notes
- Install Accessible `0.9.0`. No new migration.
- Independent grants are unchanged: they are not voided or relocated when a
  manager Access moves.
- Role-weaken via revise already voided dependents in 0.8.0 (it is not a
  silent clamp to the lower role). Trash and destroy still void dependents.
- `authorized?` still fail-closes off-root/weaker immediately. Void on move
  is the reconnect floor so the dependent is gone, not a stale sibling at
  the old node.

## [0.8.0] - 2026-09-01

### Added
- Dependent Access grants: `grant_access` can pass `depends_on:` with another
  Access recording on the same root. The dependent role cannot exceed that
  manager grant's role.
- `authorized?` and `role_for` re-check the manager invariant at authorize
  time and fail closed if the manager Access is missing, trashed, off-root,
  or weaker than the dependent — even if a void job has not run yet.
- `VoidDependentAccesses` / `VoidDependentAccessesJob` void dependent grants
  when a manager Access is revised, trashed, or destroyed.
- `depends_on_recording_id` on `recording_studio_accesses` stores the manager
  Access recording id (stable across `revise`).

### Upgrade Notes
- Run `bin/rails generate recording_studio_accessible:migrations` then
  `bin/rails db:migrate` to add `depends_on_recording_id`.
- Independent grants are unchanged. To cap a grant by another Access recording:

  ```ruby
  result = RecordingStudioAccessible.grant_access(
    recording: recording,
    actor: actor,
    role: :view,
    manager_actor: current_actor,
    depends_on: manager_access_recording
  )
  ```

- `manager_actor` is still who performed the grant. `depends_on` is the Access
  recording this grant is capped by and dies with. Do not add a second ACL.

## [0.7.0] - 2026-08-21

### Added
- `bootstrap_owner_access!` now also grants the first `:admin` on an empty
  accessible child under a shared root (for example a MessageGroup under dummy
  `MessageRoot`, or a Profile under a shared People root).

### Changed
- **Breaking dependency floor:** requires RecordingStudio `~> 4.2` (tested
  against `4.2.0`).
- Dummy app pins RecordingStudio `v4.2.0`, RecordingStudioRootSwitchable
  `v0.5.0`, and FlatPack `v0.1.133`.
- Dummy seeds bootstrap the first MessageGroup owner, then use `grant_access`
  for later members (including the through-workspace grant).
- Dummy home lists seeded message groups under the shared messages root.

### Upgrade Notes
- Upgrade RecordingStudio to `4.2.0` or newer before installing Accessible
  `0.7.0`.
- Call `bootstrap_owner_access!` on an empty owned root **or** on an empty
  accessible child under a shared root. Shared roots themselves stay rejected
  with the same message as `grant_access`.
- 0.6.1 returned `"Recording must be a root recording"` (`NON_ROOT_MESSAGE`)
  for a Profile under shared People (and dummy MessageGroup under MessageRoot).
  0.7.0 succeeds on that shape; the method still returns a result object.
- Do not bootstrap a Folder or Page under an owned Workspace just because it is
  empty.
- After a successful bootstrap, continue using `grant_access` for invites.
  Do not add an `access_management_authorizer` mutex, ENV bootstrap, or
  `AccessCreationContext.allow` workaround.
- Dummy companion pins: RecordingStudio `v4.2.0`, Root Switchable `v0.5.0`,
  FlatPack `v0.1.133`. FlatPack 0.1.133 buttons use `href:` (not `url:`),
  sidebar items use `text:` (not `label:`), and PageNav close uses
  `anchor_href:`.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.19.0...HEAD
[0.19.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.18.1...v0.19.0
[0.18.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.15.0...v0.17.0
[0.15.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.11.2...v0.12.0
[0.11.2]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.10.1...v0.11.0
[0.10.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.1...v0.3.1
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.1.0...v0.2.0
