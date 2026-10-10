# Recording Studio Accessible

Recording Studio Accessible is the optional access-control addon for `RecordingStudio`.

It extracts the access-specific pieces that currently live in RecordingStudio core into a standalone engine so host apps can install access behavior intentionally instead of assuming it is always present.

## What the gem provides

- child-only `RecordingStudio::Access` recordables for direct grants under opted-in recordings
- optional dependent grants: one Access recording can be capped by and die with another Access recording on the same root. Dependents void in place when the manager Access is revised weaker, trashed, destroyed, or moved — they do not follow a move
- optional per-action audiences (`public`, `signed_in`, `granted`, plus `register_audience`) with workspace limits and per-recording rules
- `RecordingStudioAccessible.role_for`, `role_through`, `authorized?`, `authorized_through?`, and `authorized_action?` for role lookup, grants, and named-action checks
- a mounted engine for adding, updating, and removing direct access on a recording, plus workspace-scoped actor access-point pages
- install and migration generators for host apps
- a dummy Rails app that demonstrates the addon mounted separately from RecordingStudio

## Naming

This repository follows the template rename conventions for **Recording Studio Accessible**:

- Product name: `Recording Studio Accessible`
- Gem name: `recording_studio_accessible`
- Ruby namespace: `RecordingStudioAccessible`
- Engine namespace: `RecordingStudioAccessible::Engine`

Use `RecordingStudioAccessible.*` as the public access API for new host-app code. The extracted `RecordingStudio::*` constants remain available as legacy compatibility bridges when RecordingStudio core still provides them or when this addon backfills them.

## Installation

Add the gems to your host app:

```ruby
gem "recording_studio", "~> 4.2"
gem "recording_studio_accessible"
```

Then run:

```bash
bundle install
bin/rails generate recording_studio:install
bin/rails generate recording_studio:migrations
bin/rails generate recording_studio_accessible:install
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

If you want the gem-provided mounted UI for managing direct access, then also run:

```bash
bin/rails generate recording_studio_accessible:access_management --link-helper
```

`recording_studio_accessible:install` is the base setup step. It copies the
initializer and share-email templates, and it can optionally add
`config/recording_studio_accessible.yml` for simple environment-specific
settings such as `warn_on_core_conflict`. Proc-based hooks still belong in the
initializer.

## Compatibility with RecordingStudio 4.2

Recording Studio Accessible targets RecordingStudio `4.2` (currently tested with
`4.2.0`) and its capability-owned child recordable contract. RecordingStudio core
no longer ships built-in access control, so this addon provides
`RecordingStudio::Access`, declares it as a child-only recordable, and registers
it as metadata for the `:accessible` capability.

On load, the addon registers:

```ruby
RecordingStudio.register_capability(
  :accessible,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Host recordables opt into direct access management through the addon mixin/API.
Host recordables opt into direct access management by enabling the
`:accessible` capability with RecordingStudio itself, and
RecordingStudio core derives the effective parent allowances for
`RecordingStudio::Access` from enabled capabilities.

Direct `RecordingStudio::Access` and access-recording creation are blocked when
this addon is loaded, including compatibility mode. Host applications should use
`RecordingStudioAccessible.grant_access` for direct access grants.

### Upgrading existing apps

#### Upgrading to 0.14.0

Named actions can opt into audiences. Existing `register_action` / `define_action` / `authorized_action?` behaviour is unchanged until an action is listed in `config.action_audiences`.

1. Install Accessible `0.14.0`.
2. Copy the migrations and run them.

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

3. Enable `:action_audiences` on host types that should hold audience settings. Constraints are valid only on a workspace (root). Rules live on the target item.

```ruby
RecordingStudio.enable_capability(:action_audiences, on: Workspace)
RecordingStudio.enable_capability(:action_audiences, on: PressKit)
```

4. Register any custom audiences, then configure each action. `granted` stays in every allowed set. Copy `recording_studio.accessible.audiences.*` into host locale files when you translate picker labels.

No audience picker ships in this gem. Host screens should use `audience_options_for` with a Flatpack `RadioGroup`. Staff controls belong in Recording Studio Admin.

#### Upgrading to 0.13.0

Actor access points and the engine demo/docs home pages now use Rails I18n under `recording_studio.accessible.actor_access_points.*` and `recording_studio.accessible.home.*`. English output is unchanged.

1. Install Accessible `0.13.0`. No migration.
2. Copy the new keys into host locale files when you translate those screens.
3. Controller-supplied home demo examples, generator text, and developer `ArgumentError`s stay English.

#### Upgrading to 0.12.0

Customer invitation, mail, and manage-access copy now follows Rails I18n. The gem still ships English only.

1. Install Accessible `0.12.0`. No migration.
2. Copy `recording_studio.accessible.*` from this gem's `config/locales/en.yml` into the host's `config/locales/<locale>.yml` for every language you offer.
3. Leave config callables that set subjects, actor labels, or missing-actor errors as they are. A host-supplied string still wins over the locale default.
4. Optional: set `config.access_notification_locale` to a locale or a callable if invitation and access-granted mail should not use the current request locale.

Staff actor-access-point screens, demo/docs pages, generator text, and developer `ArgumentError`s stay English.

#### Upgrading to 0.11.0

Direct grants can use role names declared on that recordable. The default list is still `view`, `edit`, and `admin`. Existing `authorized?` checks keep that hierarchy.

`recording_studio_accesses.role` becomes a string. The migration checks that every stored role is `0`, `1`, or `2`, then maps those to `view`, `edit`, and `admin`. Rollback is allowed only while every role is still `view`, `edit`, or `admin`. Once a custom role name is stored, rolling this migration back is blocked so those grants are not rewritten.

1. Install Accessible `0.11.0`.
2. Copy the migration and run it.

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

No model needs `accessible_roles` unless that context grants something other than `view`, `edit`, and `admin`. `bootstrap_owner_access!` still grants `admin`, so a context that omits `admin` cannot use it.

`authorized?` stays the ranked check. Use `authorized_for_role?` for one exact name, and `authorized_for_any_role?` when several names satisfy one capability. A dependent grant still needs `view`, `edit`, or `admin` on both the dependent and the manager.

#### Upgrading to 0.10.1

Manage access shows each person inside the table columns. No migration.

1. Install Accessible `0.10.1`.

If a host copied the old dummy Tailwind token block (`--color-primary`, `--radius-md`, and the `--color-fp-*` names) into its own stylesheet, remove that block so `data-theme="rounded"` can apply.

#### Upgrading to 0.10.0

Pending access invitations are stored on `AccessInvitation`. `RecordingStudio::Access` is still the only authorization record. `authorized?` and `role_for` ignore an invitation until it is accepted.

Previously, an unknown email using the default missing-actor handler returned a not-found error. After this release, that email in the mounted access-management flow creates a pending invitation. To keep the previous behavior, return `MissingActorResolution.invalid(...)` from the missing-actor handler.

1. Install Accessible `0.10.0`.
2. Copy the migration and run it.

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

`invite_access` uses the notice `Invitation sent.` only after the configured notifier hands the invitation off. If delivery fails, the invitation row stays and the call returns `Invitation could not be sent.` Invite again, or resend from the access page, to retry. A failed resend leaves the previously delivered token in place. The replacement token, role, manager, expiry, and last sent time are stored only after that later handoff succeeds.

#### Upgrading to 0.9.1

Cloud Agent boot files now live in this repo. Product access behavior is
unchanged. No host or schema changes.

1. Install Accessible `0.9.1`. No new migration.
2. Rebuild the Cloud Agent environment with Draft off so Build fetches the
   skill pack.

#### Upgrading to 0.9.0

Moving a manager Access recording now voids its dependents. Dependents stay at
the old node and are destroyed; they do not follow the move. Independent
grants are unchanged.

`authorized?` still fail-closes immediately if the manager is missing, trashed,
off-root, or weaker. Void is the reconnect floor after a manager move: the
dependent grant is gone rather than left as a stale sibling at the old node.

Role-weaken via `UpdateRecordingAccess` (revise) already voided dependents in
0.8.0. 0.9.0 keeps that behavior.

1. Install Accessible `0.9.0`. No new migration.
2. Independent grants do not change.
3. Do not add a second ACL. Accessible hooks the Recording parent/root change
   that Moveable's `move_to!` already persists.

#### Upgrading to 0.8.0

Dependent grants let one Access recording be capped by another Access recording
on the same root. Authorize fail-closes if that manager grant is gone, trashed,
or weaker than the dependent — even when a background void job has not run.

1. Install Accessible `0.8.0` and run:

   ```bash
   bin/rails generate recording_studio_accessible:migrations
   bin/rails db:migrate
   ```

2. Existing independent grants do not change. `manager_actor` is still who
   performed the grant.
3. To declare a dependency, pass the manager Access recording:

   ```ruby
   result = RecordingStudioAccessible.grant_access(
     recording: recording,
     actor: actor,
     role: :view,
     manager_actor: current_actor,
     depends_on: manager_access_recording
   )
   raise result.error if result.failure?
   ```

4. The dependent role cannot exceed the manager grant's role. The manager must
   be an active Access recording on the same root. Do not invent a second ACL
   or OAuth-specific grant helper — keep using `grant_access` / `authorized?`.

#### Upgrading to 0.7.0

`bootstrap_owner_access!` now covers two empty first-owner shapes:

- an owned root (`shared: false`), such as a Workspace
- an accessible child under a shared root, such as a Profile or a MessageGroup

1. Upgrade RecordingStudio to `~> 4.2` (tag `v4.2.2`).
2. Keep calling bootstrap on a new empty owned root. That path is unchanged.
3. For shared forests, create the accessible child first, then bootstrap on
   **that child** — never on the shared root itself:

  ```ruby
  group = MessageGroup.create!(message_root: message_root, name: "Launch", summary: "…")
  recording = RecordingStudio::Recording.unscoped.find_by!(recordable: group)
  result = RecordingStudioAccessible.bootstrap_owner_access!(
    recording: recording,
    actor: user
  )
  raise result.error if result.failure?
  ```

   Hosts such as `recording_studio_users` can call the same method on a Profile
   under a shared People root. Dummy class names stay `MessageRoot` /
   `MessageGroup`; README examples may say `MessagesRoot` for the same pattern.

   0.6.1 returned `result.error == "Recording must be a root recording"`
   (`NON_ROOT_MESSAGE`) for that child because `root_recording?` was false and
   `shared_root?` was false, so validation never reached shared-root denial.
   The method still does not raise; check `result.success?`.
4. Use `grant_access` for every later invite or membership change.
5. Do not add an `access_management_authorizer` mutex, ENV bootstrap, or
   `AccessCreationContext.allow` workaround. Bootstrap is the first-owner API.
6. If you use the dummy app or copy its companion gems, pin:
   - `recording_studio` to tag `v4.2.2`
   - `recording_studio_root_switchable` to tag `v0.5.0`
   - `flat_pack` to tag `v0.1.133`

#### Upgrading to 0.6.1

This release adds `RecordingStudioAccessible.bootstrap_owner_access!` for the
first admin on an empty owned root.

1. Replace demo/production workarounds that used
   `ENV["RECORDING_STUDIO_ACCESSIBLE_BOOTSTRAP_ADMIN"]`, temporary
   `access_management_authorizer` overrides, or host-facing
   `AccessCreationContext.allow` for first-owner setup.
2. After creating and persisting an owned root (for example a Workspace with
   `shared: false`), call:

  ```ruby
  root = RecordingStudio.root_recording_for(workspace)
  result = RecordingStudioAccessible.bootstrap_owner_access!(
    recording: root,
    actor: user
  )
  raise result.error if result.failure?
  ```

3. Use `grant_access` for every subsequent invite or membership change.
4. Do not call bootstrap on shared roots. Shared forests keep grants on
   descendants beneath the shared root.

#### Upgrading to 0.6.0

This release requires RecordingStudio `4.1.0` and adds shared-root access rules.

1. Upgrade RecordingStudio to `~> 4.1` (tag `v4.1.0` or newer).
2. If you use shared roots, declare them with `shared: true` on root recordables and enable `:accessible` on domain children beneath the shared root — not on the shared root itself:

  ```ruby
  class MessagesRoot < ApplicationRecord
    recording_studio_recordable label: "Messages", root: true, shared: true
  end

  class MessageGroup < ApplicationRecord
    recording_studio_recordable label: "Message group",
                                root: false,
                                allowed_parent_types: ["MessagesRoot"]
    RecordingStudio.enable_capability(:accessible, on: self)
  end
  ```

3. New grants and updates on shared roots are rejected. Revoke legacy shared-root grants if you still have them.
4. `root_recordings_for` and `root_recording_ids_for` exclude shared roots from actor-owned bucket lists. Descendant authorization is unchanged.
5. If you use the dummy app or copy its companion gems, pin:
   - `recording_studio` to tag `v4.1.0`
   - `recording_studio_root_switchable` to tag `v0.4.0`

#### Upgrading to 0.5.1

This is a dependency refresh. There are no access-API changes.

1. Stay on RecordingStudio `~> 3.0`. This gem is tested with `3.0.3`.
2. If you use the dummy app or copy its companion gems, pin:
   - `recording_studio` to tag `v3.0.3`
   - `recording_studio_root_switchable` to tag `v0.3.5`
   - `flat_pack` to tag `v0.1.129` (this jumps ViewComponent from 3 to 4)
3. Do not upgrade to RecordingStudio `4.0` with this release. Root switching
   `0.3.5` still requires RecordingStudio `~> 3.0`.

#### Upgrading to 0.5.0

Version 0.5.0 changes new-grant handling and effective-role resolution.

1. Configure the polymorphic types that may receive new grants before deploying:

  ```ruby
  RecordingStudioAccessible.configure do |config|
    config.access_actor_types = ["User", "Workspace"]
  end
  ```

  A blank or `nil` value now rejects every new grant. Use `:all` only when the
  application intentionally supports arbitrary persisted actor types. Existing
  grants remain readable, effective, revocable, and updatable.

2. Review authorization flows that assumed a weaker direct grant on a child
  recording restricted access inherited from an ancestor. Effective access now
  uses the strongest valid role across the target recording and its applicable
  ancestors.

3. Inspect pre-existing same-parent duplicate grants before deployment:

  ```bash
  bin/rails recording_studio_accessible:access_grants:integrity
  ```

  Review the dry-run output before repair. No database migration is required.

If your app previously created direct grants with `RecordingStudio::Access.create!`
plus a matching `RecordingStudio::Recording`, or by calling
`parent_recording.record(RecordingStudio::Access, ...)`, update that code to use
`RecordingStudioAccessible.grant_access` instead.

Before:

```ruby
access = RecordingStudio::Access.create!(actor: user, role: :view)

RecordingStudio::Recording.unscoped.create!(
  root_recording_id: recording.id,
  parent_recording_id: recording.id,
  recordable: access
)
```

Or:

```ruby
parent_recording.record(
  RecordingStudio::Access,
  actor: user,
  parent_recording: parent_recording
) do |access|
  access.actor = user
  access.role = :view
end
```

After:

```ruby
result = RecordingStudioAccessible.grant_access(
  recording: recording,
  actor: user,
  role: :view,
  manager_actor: current_actor
)

raise result.error if result.failure?
```

When this addon is loaded, unsupported direct creation now raises
`ActiveRecord::RecordInvalid` with the validation message:

```text
Create access grants through RecordingStudioAccessible.grant_access
```

The supported grant path keeps placement checks, authorization checks, role
validation, and duplicate-grant deduplication in one place.

## Setup notes

### RecordingStudio configuration

Your host app still configures RecordingStudio the normal way:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace"]
  config.actor = -> { Current.actor }
end
```

RecordingStudio `4.1` requires each configured recordable to declare its
hierarchy rules. Domain child recordables still declare their static parents:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace"]
end
```

The addon automatically registers `RecordingStudio::Access` when it loads,
declares it as `root: false`, and registers it as a child recordable owned by the
`:accessible` capability. To allow direct access grants beneath a host
recordable, enable that capability in host application code:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true

  RecordingStudio.enable_capability(:accessible, on: self)
end
```

The RecordingStudio declaration controls the host recordable hierarchy.
`RecordingStudio.enable_capability(:accessible, on: ...)` enables the
`:accessible` capability for that recordable type, and RecordingStudio core
derives effective parent allowances for `RecordingStudio::Access` from that
capability state. Without that enablement, the mounted access-management UI and
grant service reject direct access placements for the recordable.

### Shared roots

RecordingStudio 4.1 adds type-level shared roots for domain forests such as
messages. Shared roots remain real tree roots for writes and queries, but they
are not actor-owned buckets.

Do **not** enable `:accessible` on a shared root type. Enable it on domain
children beneath the shared root, then bootstrap the first owner on that child.

README examples use `MessagesRoot` as the shared-forest type name. The dummy
app class is `MessageRoot` — same pattern, keep dummy names as they are.

```ruby
class MessagesRoot < ApplicationRecord
  recording_studio_recordable label: "Messages", root: true, shared: true
end

class MessageGroup < ApplicationRecord
  recording_studio_recordable label: "Message group",
                              root: false,
                              allowed_parent_types: ["MessagesRoot"]
  RecordingStudio.enable_capability(:accessible, on: self)
end
```

Accessible rejects new and updated direct grants on shared roots. Legacy grants
can still be revoked. Mounted access management returns `404` for shared roots.
`root_recordings_for` and `root_recording_ids_for` exclude shared roots from
actor-owned bucket lists while descendant authorization continues to work.

Useful RecordingStudio 4 introspection helpers:

```ruby
RecordingStudio.capability_child_recordables_for(:accessible)
# => ["RecordingStudio::Access"]

RecordingStudio.capability_child_recordables_for(:action_audiences)
# => ["RecordingStudio::AccessConstraint", "RecordingStudio::AccessRule"]

RecordingStudio.capability_allowed_parent_types_for("RecordingStudio::Access")
# => ["Workspace"] # plus any other opted-in host types

RecordingStudio.declared_allowed_parent_types_for("RecordingStudio::Access")
# => []

RecordingStudio.allowed_parent_types_for("RecordingStudio::Access")
# => ["Workspace"] # effective capability-derived parents

RecordingStudio.recordable_parent_allowances_for("RecordingStudio::Access")
# => { "recording_studio_accessible" => ["Workspace"] }
```

### Granting access

```ruby
recording = RecordingStudio.root_recording_for(workspace)

RecordingStudioAccessible.grant_access(
  recording: recording,
  actor: user,
  role: :view,
  manager_actor: current_actor
)
```

`actor` is the polymorphic object receiving access. It can be a user,
workspace, company, team, system actor, or another configured access actor.
`manager_actor` remains the actor performing the access-management action.

A grant may also depend on another Access recording on the same root. The
dependent role cannot exceed that manager grant's role, and
`authorized?` / `role_for` fail closed if the manager Access is later
trashed, destroyed, off-root, or downgraded. A background void job then
destroys the dependent grant in place. If the manager Access recording is
moved, dependents stay at the old node and are voided — they do not follow
the move. Independent grants are not voided or relocated.

```ruby
result = RecordingStudioAccessible.grant_access(
  recording: recording,
  actor: other_actor,
  role: :view,
  manager_actor: current_actor,
  depends_on: manager_access_recording
)
```

Independent grants omit `depends_on` and keep the previous behavior.

### Bootstrapping the first owner

A brand-new owned root or a brand-new accessible child under a shared root has
zero access grants, so the default access-management authorizer (which requires
an existing `:admin`) cannot authorize the creator's first grant. Use
`bootstrap_owner_access!` for that one-shot setup:

```ruby
workspace = Workspace.create!(name: "Acme")
root = RecordingStudio.root_recording_for(workspace)

result = RecordingStudioAccessible.bootstrap_owner_access!(
  recording: root,
  actor: user
)
raise result.error if result.failure?
# result.value => the Access recording (same shape as grant_access success)

group_recording = RecordingStudio::Recording.unscoped.find_by!(recordable: message_group)
result = RecordingStudioAccessible.bootstrap_owner_access!(
  recording: group_recording,
  actor: user
)
raise result.error if result.failure?
```

| Situation | API |
| --- | --- |
| Empty owned root, first admin | `bootstrap_owner_access!` |
| Empty accessible child under a shared root, first admin | `bootstrap_owner_access!` |
| Invites, membership, role changes after that | `grant_access` / mounted access UI / Users membership |

Bootstrap succeeds when the recording is persisted, `:accessible` is enabled on
its recordable type, the actor type is allowlisted, and there are zero active
direct Access children (or the only grant is already this actor as `:admin`,
which is treated as an idempotent success). It always creates role `:admin`.

Allowed recording shapes:

- an owned root (`shared: false`), such as Workspace
- a non-root descendant whose root type is `shared: true`, such as MessageGroup
  under dummy `MessageRoot` (README examples may say `MessagesRoot`)

Still rejected:

- the shared root itself
- owned-root children such as a Folder or Page under Workspace
- recordings without `:accessible`
- non-allowlisted or unpersisted actors and recordings

Shared roots are rejected with the same message as grant_access:

```text
Grant access on objects below a shared root, not on the shared root itself.
```

Intended callers are host apps and `recording_studio_users` create-first-root
or create-first-profile flows — not automatic wiring inside
`root_recording_for`. Treat bootstrap as a trusted host/setup call: anyone who
can invoke it on an allowed empty recording becomes that recording's first
admin.

Do not use ENV authorizer overrides, `access_management_authorizer` mutexes, or
`AccessCreationContext.allow` as the product path for first-owner setup.

New access grants fail closed until host apps explicitly configure which
polymorphic actor types may receive them. Use a finite allowlist in production:

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_actor_types = ["User", "Workspace", "Company", "Team"]
end
```

Strings and classes are supported; classes are normalized to their base
polymorphic type, so STI subclasses match their stored base type. Blank lists
and `nil` reject every new grant. Grant subjects must be persisted records.

Hosts that intentionally support arbitrary persisted polymorphic subjects may
opt in with the exact symbol `:all`:

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_actor_types = :all
end
```

This is security-sensitive: `"all"`, `"*"`, and other values do not enable it.
Prefer an explicit allowlist whenever the valid subject classes are known.
This setting only admits *new* grants. Existing access records remain readable,
revocable, and effective for `role_for` and `authorized?` after the allowlist
is changed or removed.

The mounted actor access-point page also depends on a finite allowlist. It
fails closed for blank configuration and for `:all`; `:all` never broadens
request-driven type lookup, so request params cannot probe arbitrary application
constants.

For example, a host app may grant access to a workspace:

```ruby
RecordingStudioAccessible.grant_access(
  recording: message_group_recording,
  actor: workspace,
  role: :edit,
  manager_actor: current_user
)
```

RecordingStudio Accessible treats `RecordingStudio::Access` as an internal
recordable. Applications should not create access records directly. Use
`RecordingStudioAccessible.bootstrap_owner_access!` for the first owner on an
empty owned root or empty accessible child under a shared root, then
`RecordingStudioAccessible.grant_access` or
`RecordingStudioAccessible::Services::GrantRecordingAccess` thereafter.
When this addon is loaded, direct access grant creation raises a validation
error.

The supported grant path enforces placement, authorization, role validation, and
deduplication so each actor has at most one direct active access grant under a
given parent recording. The same actor may hold separate direct grants beneath
different hierarchy nodes. Supported grant APIs update the retained grant and
remove redundant active same-parent grants during ordinary writes.

### Duplicate grant integrity

Malformed legacy data, direct SQL imports, and callback-skipping imports can
still leave redundant rows behind. Lookup remains fail-safe: when more than one
active direct grant exists for the same actor under one parent, authorization
uses the strongest valid role for that parent. This is defense in depth, not
support for maintaining duplicate grants.

Inspect a host application's active direct grants without modifying data:

```bash
bin/rails recording_studio_accessible:access_grants:integrity
```

The task reports each duplicate group by parent recording, normalized actor
type/ID, access recording IDs, roles, and the recording it would retain. To
repair groups, provide an explicit audit actor GlobalID and opt out of dry-run
mode:

```bash
DRY_RUN=false MANAGER_ACTOR_GID="gid://your-app/User/123" \
  bin/rails recording_studio_accessible:access_grants:integrity
```

Repair locks and re-queries each parent, retains one active recording, promotes
it to the strongest valid role, and removes redundant recording/recordable pairs
through the normal lifecycle. Groups containing no valid role are reported and
left untouched for manual investigation. Each parent group is repaired in its
own transaction: later failures do not undo groups already repaired, and the
task prints every attempted group before exiting nonzero for a partial failure.

### Managing access through the mounted engine

If you mount `RecordingStudioAccessible::Engine`, the gem exposes recording-
scoped access management pages at:

```text
/recording_studio_accessible/recordings/:recording_id/accesses
```

Those pages use a blank layout, render FlatPack-based UI, and let authorized
users add, update, and remove direct grants for the target recording.

The mounted engine also exposes workspace-scoped actor access-point pages at:

```text
/recording_studio_accessible/workspaces/:workspace_id/actor_access_points?actor_type=User&actor_id=...
```

That page shows the current actor's own access points, or another actor's
access points when the viewer is allowed to manage access for the workspace
root recording.

The mounted addon overview, docs, and email-preview pages under `/recording_studio_accessible` are authorized separately from the recording-scoped access-management page. By default they are fail-closed unless the current actor has admin access to the resolved demo root recording. If your host app wants a different policy, override `config.mounted_page_authorizer`.

To set that up in a host app, run:

```bash
bin/rails generate recording_studio_accessible:access_management --link-helper
```

That generator:

- mounts `RecordingStudioAccessible::Engine` if it is not already mounted
- creates `config/initializers/recording_studio_accessible.rb` only when it is still missing
- copies overrideable share-email templates to `app/views/recording_studio_accessible/access_granted_mailer/` only when they are still missing
- optionally creates a host helper with `recording_access_management_path` and `recording_access_management_link`

`AccessInvitation` records pending intent for an email address. `RecordingStudio::Access` records authorization for a persisted actor. `authorized?` and `role_for` read access grants only.

`invite_access` calls `grant_access` when the email already belongs to an actor. Otherwise it stores one unclosed `AccessInvitation` for that recording and email. Unclosed means not accepted and not revoked. An expired invitation stays in that slot, and a later invite refreshes the same row instead of inserting another one. After the invited person authenticates, `accept_access_invitation` calls `grant_access` and stamps the invitation accepted. `revoke_access_invitation` withdraws a pending invitation and leaves any access grant alone.

By default, the new-access form resolves the email with `access_management_actor_email_resolver`. A matching actor is granted immediately. An unknown email returns `MissingActorResolution.unresolved`, and the access controller calls `invite_access`. A host handler that returns `:invited` has already finished its own hand-off. The addon stores nothing in that case.

After a successful grant, the default notifier sends `RecordingStudioAccessible::AccessGrantedMailer` using the copied templates above. Invitation mail uses `AccessInvitationMailer` and the acceptance URL. You can override the lookup step, missing-user behavior, invitation delivery, share-email subject, destination URL, or the notifier itself:

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_management_actor_email_resolver = lambda do |controller:, email:|
    User.find_by(email: email.to_s.strip.downcase)
  end
  config.access_management_current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end
  config.access_management_missing_actor_handler = lambda do |controller:, email:, **|
    normalized_email = email.to_s.strip.downcase
    next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?

    RecordingStudioAccessible::MissingActorResolution.redirect(
      location: controller.main_app.url_for(
        controller: "/users",
        action: :new,
        email: normalized_email,
        only_path: true
      ),
      alert: "Review #{normalized_email} before granting access",
      status: :requires_resolution
    )
  end
  config.access_invitation_ttl = 14.days
  config.access_invitation_actor_matcher = lambda do |actor:, email:|
    actor.respond_to?(:email) && actor.email.to_s.strip.downcase == email
  end
  config.access_invitation_url_resolver = lambda do |raw_token:, **|
    "https://example.com/invitations/#{raw_token}"
  end
  config.access_invitation_sign_in_url_resolver = lambda do |controller:, token:, **|
    controller.main_app.new_user_session_path(return_to: token)
  end
  config.access_management_access_granted_subject = lambda do |recording:, **|
    "A recording was shared with you: #{RecordingStudio::Labels.title_for(recording.recordable)}"
  end
  # Optional. Invitation and access-granted mail render inside I18n.with_locale.
  # Default is the current locale (the inviter's request). Pass a locale, or a
  # callable that returns one from the recipient email, without storing a column.
  config.access_notification_locale = lambda do |email:, **|
    User.find_by(email: email)&.preferred_locale.presence || I18n.locale
  end
  config.access_management_access_granted_url_resolver = lambda do |controller:, recording:, **|
    controller.main_app.root_url
  end
  config.access_management_actor_label = ->(actor) { actor.email }
  config.access_management_authorizer = lambda do |recording:, actor:, **|
    actor.present? && RecordingStudioAccessible.authorized?(
      actor: actor,
      recording: recording,
      role: :admin
    )
  end
  config.mounted_page_authorizer = lambda do |controller:, actor:, recording:|
    actor.present? && recording.present? && RecordingStudioAccessible.authorized?(
      actor: actor,
      recording: recording,
      role: :admin
    )
  end
end
```

Host views with FlatPack available can render the compact access UI with:

```erb
<%= recording_studio_accessible_avatars(recording, button_style: :primary) %>
```

The helper only renders for actors authorized to manage access for the recording. It fetches the recording's access holders through Recording Studio Accessible and renders a FlatPack avatar group when configured avatar data is available. Configure `avatar_resolver` to map each access holder object to presentation data; return `nil` when an object should not render as an avatar:

```ruby
RecordingStudioAccessible.configure do |config|
  config.avatar_resolver = ->(access_holder) do
    {
      name: access_holder.profile_name,
      image_url: access_holder.profile_avatar_url
    }
  end
end
```

When no access holders exist, or no holders resolve to avatar data, the helper renders a `"+ Access"` FlatPack button. Pass `button_style:` to customize that fallback button.

The missing-actor handler may return an actor, or a `RecordingStudioAccessible::MissingActorResolution`. An actor or `MissingActorResolution.created(...)` grants immediately. `:unresolved` asks the controller to call `invite_access`. `:invited` means the host already handled the invitation, and the addon stores nothing. `:invalid` and `:redirect` keep their previous behavior. Edit the copied templates under `app/views/recording_studio_accessible/access_granted_mailer/` when the grant mail is close. Replace `config.access_management_access_granted_notifier` when delivery has to change.

By default, the mounted engine resolves the acting user from `Current.actor` so it follows the same actor source that RecordingStudio uses. If your host app needs a different source, override `config.access_management_current_actor_resolver`. The built-in resolver only falls back to `controller.current_user` when `Current.actor` is unavailable.

The mounted create flow works like this:

1. The controller asks `access_management_actor_email_resolver` for an actor.
2. A resolved actor is granted with `GrantRecordingAccess`, and the access-granted notifier runs.
3. No actor means the controller calls `access_management_missing_actor_handler`.
4. An actor or `:created` from that handler is granted the same way.
5. `:unresolved` (the default for an unknown email) calls `invite_access`, which stores one unclosed invitation and asks the invitation notifier to hand it off.
6. `:invited`, `:invalid`, and `:redirect` stay on their existing branches. `:invited` does not store an invitation.

`invite_access` does not call the missing-actor handler. Use it when the caller already wants a grant or a pending invitation:

```text
invite_access
    |
    +-- actor exists --> grant_access
    |
    +-- actor missing --> AccessInvitation
                              |
                              v
                         actor signs up / authenticates
                              |
                              v
                    accept_access_invitation
                              |
                              v
                         grant_access
```

Account lookup stays in the host resolver. Pending intent stays on `AccessInvitation`. Authorization stays on `RecordingStudio::Access`, written only by `grant_access`.

`invite_access` returns `Invitation sent.` only after `deliver_access_invitation` reports a successful handoff. A failed handoff returns `Invitation could not be sent.`

The first invitation is stored before delivery. That row stays if the first handoff fails, so a later invite can retry. A resend keeps the existing token, role, manager, expiry, and last sent time when delivery fails. Those fields are replaced together only after the replacement handoff succeeds.

A custom `access_invitation_notifier` signals that outcome directly. Return a truthy value, such as the delivered mail, for success. Return `false`, `nil`, or an object whose `success?` is false for failure. A raised error is failure too. The default notifier returns failure when it cannot build an acceptance URL, and it does not send that mail.

### Checking access

Effective access is the strongest role granted to the actor on the target
recording or any applicable ancestor up to the root. Direct grants are additive
and do not restrict stronger inherited access.

For example, if the root grants `admin` and a child directly grants `view`, the
child's direct role remains `view` while its effective role is `admin`.

```ruby
RecordingStudioAccessible.role_for(actor: user, recording: root_recording)
RecordingStudioAccessible.authorized?(actor: user, recording: root_recording, role: :edit)

# Equivalent namespaced form:
RecordingStudioAccessible::Authorization.allowed?(actor: user, recording: root_recording, role: :edit)
```

Existing checks remain exact actor checks. For example, this checks whether the
workspace itself has edit access to the recording:

```ruby
RecordingStudioAccessible.authorized?(
  actor: workspace,
  recording: message_group_recording,
  role: :edit
)
```

It does not check whether a user can use the workspace's access.

### Context roles

A recordable with no `accessible_roles` declaration uses `view`, `edit`, and `admin`. `authorized?` still treats those as a hierarchy. `view` satisfies a view check. `edit` satisfies view and edit. `admin` satisfies all three. `RecordingStudio::AccessRoles::ORDER` stays that map. It is not a host setting.

Declare direct role names on the recordable that receives the grant.

```ruby
class LibraryItem < ApplicationRecord
  recording_studio_recordable label: "Library item", root: false, allowed_parent_types: ["Workspace"]
  RecordingStudio.enable_capability(:accessible, on: self)

  accessible_roles :view, :download
end
```

The declaration needs one or more unique names. Blank names are rejected. The order you write is the order manage access shows. The access row stores the chosen name, such as `"download"`. It does not store the declaration.

Only those names can be granted, updated, or invited on that recording. A normal workspace still accepts `view`, `edit`, and `admin`, and rejects `download`. A library item accepts `view` and `download`, and rejects `edit`.

Ancestor grants are not rewritten to the target list. A parent `edit` grant stays `edit`.

`authorized?` is the ranked check. It uses `view < edit < admin` and ignores a name outside that list.

```ruby
RecordingStudioAccessible.authorized?(
  actor: current_user,
  recording: recording,
  role: :edit
)
```

`authorized?(role: :download)` is false. `download` has no rank.

`authorized_for_role?` asks whether that exact name is on the recording or an ancestor. It matches `download` and `edit` the same way. An inherited `edit` grant does not satisfy `role: :download`.

```ruby
RecordingStudioAccessible.authorized_for_role?(
  actor: current_user,
  recording: recording,
  role: :download
)
```

`authorized_for_any_role?` is true when any listed name is on that path. You choose the names that satisfy one capability. Accessible does not treat `download` as `edit` because they sit in the same position in two lists.

```ruby
RecordingStudioAccessible.authorized_for_any_role?(
  actor: current_user,
  recording: recording,
  roles: [:download, :edit, :admin]
)
```

A download check that should also allow editors passes `[:download, :edit, :admin]`. An API check that should not allow downloaders passes `[:api, :admin]`.

Dependent grants still compare only `view`, `edit`, and `admin`. If the dependent role or the manager role is outside that ranking, the grant fails with "Dependent access requires a ranked role". Direct grants and the two exact-name checks still accept the declared name.

`roles_for(recording)` returns the declared names. `role_valid_for?(recording, role)` is the direct-grant check. Manage access renders those names, humanized. A library item shows View and Download.

### Authorizing named actions

Use ordinary recording access for existing recordings. Use action authorization
when an addon or host app needs to ask whether an actor may perform a named
operation, optionally in a recording context:

```ruby
RecordingStudioAccessible.authorized_action?(
  actor: current_actor,
  action: :"recording_studio_messages.create_group",
  recording: site_messages_recording,
  context: {
    messages_key: :site_messages,
    child_type: "RecordingStudioMessages::MessageGroup"
  },
  controller: self
)
```

The `recording:` argument is optional because some checks are global app-level
questions, such as `:signed_in`, `:subscribed`, `:staff`, or `:account_owner`.
Actions that require a recording context should declare that explicitly:

```ruby
RecordingStudioAccessible.register_action(
  :"recording_studio_messages.create_group",
  label: "Create message group",
  description: "Allows an actor to start a new message group under a messages container.",
  source: "recording_studio_messages",
  recording_required: true
)
```

Registration stores metadata only. It does not grant permission. Host apps
define the action policy separately:

```ruby
RecordingStudioAccessible.define_action(
  :"recording_studio_messages.create_group"
) do |actor:, **|
  actor.present? && actor.respond_to?(:subscribed?) && actor.subscribed?
end
```

Actions fail closed when the action is blank, no policy is defined, a policy
raises, or a `recording_required: true` action is checked without a recording.
Defining a policy for an unregistered action is allowed so host apps can define
app-local actions without a separate metadata registration. Re-defining an
action or check intentionally replaces the previous block, which keeps Rails
development reloads deterministic. Action and check names must be symbols; do
not pass raw params directly as action names.

In Rails apps, define reloadable action policies from a reload-safe hook:

```ruby
Rails.application.config.to_prepare do
  RecordingStudioAccessible.define_action(:subscribed) do |actor:, **|
    actor.present? && actor.respond_to?(:subscribed?) && actor.subscribed?
  end
end
```

Reusable checks can be composed inside action policies:

```ruby
RecordingStudioAccessible.define_check(:subscribed) do |actor:, **|
  actor.present? && actor.respond_to?(:subscribed?) && actor.subscribed?
end

RecordingStudioAccessible.define_action(
  :"recording_studio_messages.create_group"
) do |actor:, recording:, context:, controller:, **|
  RecordingStudioAccessible.check(
    :subscribed,
    actor: actor,
    recording: recording,
    context: context,
    controller: controller
  )
end
```

Global checks can be authorized without a recording:

```ruby
RecordingStudioAccessible.register_action(
  :subscribed,
  label: "Subscribed",
  source: "application"
)

RecordingStudioAccessible.define_action(:subscribed) do |actor:, **|
  actor.present? && actor.respond_to?(:subscribed?) && actor.subscribed?
end

RecordingStudioAccessible.authorized_action?(actor: current_actor, action: :subscribed)
```

Feature addons should use namespaced action names. Examples:

```ruby
RecordingStudioAccessible.register_action(
  :"recording_studio_exportable.export",
  label: "Export recording",
  source: "recording_studio_exportable",
  recording_required: true
)

RecordingStudioAccessible.define_action(
  :"recording_studio_exportable.export"
) do |actor:, recording:, **|
  RecordingStudioAccessible.authorized?(
    actor: actor,
    recording: recording,
    role: :admin
  )
end

RecordingStudioAccessible.register_action(
  :"recording_studio_publishable.publish",
  label: "Publish recording",
  source: "recording_studio_publishable",
  recording_required: true
)

RecordingStudioAccessible.register_action(
  :"recording_studio_duplicatable.duplicate",
  label: "Duplicate recording",
  source: "recording_studio_duplicatable",
  recording_required: true
)
```

Registered actions and policies are introspectable:

```ruby
RecordingStudioAccessible.registered_actions
RecordingStudioAccessible.registered_action?(:"recording_studio_messages.create_group")
RecordingStudioAccessible.action_registration_for(:"recording_studio_messages.create_group")
RecordingStudioAccessible.defined_actions
RecordingStudioAccessible.action_defined?(:"recording_studio_messages.create_group")
```

> Do not grant broad access to a shared root just to allow users to create
> private children. Use an action permission such as
> `recording_studio_messages.create_group` instead, then grant ordinary access
> directly on the created child recording.

### Action audiences

Grants say who holds a role on a recording. Audiences say who may attempt one
named action. They are opt-in and keyed by action. A kit download rule never
affects a private-data export.

Built-in audiences:

- `public` — anyone, including a nil actor
- `signed_in` — `actor.present?`
- `granted` — `authorized_for_any_role?` against that action's `granted_roles`

Register more audiences in the host or a consuming gem. Predicates run
server-side. Unknown audiences, missing policies, invalid config, and predicate
exceptions deny.

```ruby
RecordingStudioAccessible.register_audience(
  :"presskits.verified_journalist",
  label_key: "recording_studio_presskits.audiences.verified_journalist"
) do |actor:, recording:, context:|
  actor.present? && actor.respond_to?(:verified_journalist?) && actor.verified_journalist?
end

RecordingStudioAccessible.configure do |config|
  config.action_audiences[:"presskits.kit_download"] = {
    allowed: %i[signed_in granted],
    default: :granted,
    granted_roles: %i[download edit admin],
    granted_override: true,
    manage_role: :admin
  }
end
```

`granted` cannot be removed from an allowed set. If an action has no valid
granted roles, effective audience is an internal `denied`. `public` is never
implied; add it explicitly. `granted_override` defaults to false: when true, an
actor who already holds a granted role passes even if the selected audience is
narrower. Domain conditions (publication, exports) stay in the consuming gem.

Accessible stores two child recordables under types that enable
`:action_audiences`:

- `RecordingStudio::AccessConstraint` — `action`, `allowed_audiences`. Root
  only. Can only narrow the host `allowed` list.
- `RecordingStudio::AccessRule` — `action`, `audience`. Lives on the target
  recording. At most one live rule per action per recording.

Do not insert those rows yourself. Use the public API:

```ruby
RecordingStudioAccessible.effective_audience(recording: kit, action: :"presskits.kit_download")
RecordingStudioAccessible.audience_options_for(recording: kit, action: :"presskits.kit_download")
# => [{ audience: :signed_in, label: "Signed in" }, { audience: :granted, label: "People with access" }]

RecordingStudioAccessible.set_audience!(
  recording: kit,
  action: :"presskits.kit_download",
  audience: :signed_in,
  actor: current_actor
)

RecordingStudioAccessible.set_audience_constraint!(
  root: workspace_root,
  action: :"presskits.kit_download",
  allowed_audiences: %i[granted],
  actor: current_actor
)
```

`set_audience!` requires `manage_role` on the recording. `set_audience_constraint!`
requires `:admin` on the root. Narrowing a workspace rewrites descendant rules
whose audience is no longer allowed to `granted` (revision plus an
`audience_fallback` event). Relaxing the limit later does not restore the old
audience; someone with `manage_role` must pick it again.

Accessible supplies the `define_action` policy for every action in
`action_audiences`. `authorized_action?` then checks the effective audience,
or the granted role when `granted_override` is on. Actions that are not
configured keep their existing host policies.

This gem does not ship an audience picker. Use `audience_options_for` with a
Flatpack `RadioGroup` on the host screen. Staff limits belong in Recording
Studio Admin.

### Access through another actor

`RecordingStudio::Access` stores a polymorphic actor. The actor is the access
subject. In addition to users, host apps may grant access to workspaces,
companies, teams, system actors, or other configured actor types.

Use `authorized_through?` when one actor should use another actor's access
grant:

```ruby
RecordingStudioAccessible.authorized_through?(
  actor: current_user,
  through: workspace,
  recording: message_group_recording,
  role: :edit
)
```

This returns true only when `current_user` is allowed to act through
`workspace` and `workspace` has edit access to the message group.

Use `role_through` to return the effective role from the through actor:

```ruby
RecordingStudioAccessible.role_through(
  actor: current_user,
  through: workspace,
  recording: message_group_recording
)
# => :edit
```

Configure through authorization in the host app:

```ruby
RecordingStudioAccessible.configure do |config|
  config.authorize_actor_through = lambda do |actor:, through:, recording: nil, role: nil, controller: nil, **|
    case through
    when Workspace
      workspace_root = RecordingStudio.root_recording_for(through)

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: workspace_root,
        role: :view
      )
    else
      actor == through
    end
  end
end
```

By default, actors may only act through themselves. If the hook raises,
through authorization fails closed.

Existing `authorized?`, `role_for`, `root_recordings_for`, and
`access_recordings_for_actor` calls remain exact actor checks. They do not
automatically use workspace, company, or team access. Use
`authorized_through?` or `role_through` when you explicitly want one actor to
use another actor's access grant.

## Internationalization

The gem ships **English only** in `config/locales/en.yml`. Keys nest under `recording_studio.accessible.*`:

```ruby
t("recording_studio.accessible.manage.title")
t("recording_studio.accessible.actor_access_points.title", actor: label)
t("recording_studio.accessible.home.overview.title")
t("recording_studio.accessible.flashes.invitation_sent")
t("recording_studio.accessible.mailers.invitation.subject_with_recording", recording: name)
```

Customer invitation and manage-access screens, actor access points, and the engine demo/docs home pages use these keys. Developer examples passed from `HomeController` stay English. Hosts own other languages. Copy `recording_studio.accessible.*` into `config/locales/<locale>.yml` and list that locale in `config.i18n.available_locales`. Do not add `RecordingStudio_Internationalization` as a dependency of this gem — it is optional on the host (the dummy uses it to switch English/French).

Config callables still win. If you set `access_invitation_subject`, `access_management_access_granted_subject`, `access_management_actor_label`, or a missing-actor error string, that copy is used instead of the locale default.

Role labels look up `recording_studio.accessible.roles.<name>` and fall back to the current humanize, so a custom host role still has a label.

Invitation and access-granted mail render inside `I18n.with_locale`. The default locale is the current one (the inviter's request when they send the mail). Set `config.access_notification_locale` to a locale or a callable when the host already knows the recipient's language. This gem does not add a locale column.

Stored names stay data: recording titles, people names, emails, and type names are not translated. Mailer bodies are whole-sentence keys with interpolation so translators see the full sentence.

Generator CLI text, developer-facing `ArgumentError`s, and controller-supplied demo examples on the home docs pages stay English.

Add [Recording Studio Internationalization](https://github.com/bowerbird-app/RecordingStudio_Internationalization) on the host when you want a language selector.

## Dummy app demo

The dummy app lives in `test/dummy/` and demonstrates Recording Studio Accessible on top of RecordingStudio. It pins the companion gems this addon is tested with: RecordingStudio `v4.4.0`, RecordingStudioRootSwitchable `v0.5.0`, FlatPack `v0.1.208`, and (dummy only) Recording Studio Internationalization `v0.1.2`. Dummy layouts use FlatPack's rounded theme (`data-theme="rounded"`). The dummy Tailwind entry does not redeclare those color or radius tokens. Dummy offers English and French. The language selector sits in the top nav, to the left of the workspace switcher. French keys live in `test/dummy/config/locales/fr.yml`. The engine does not ship French.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

The dummy app configures actor types, through-authorization, and avatars in `test/dummy/config/initializers/recording_studio_accessible.rb`. It leaves an unknown email as an invitation until the signup page creates the user and accepts.

Run it with:

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/rails tailwindcss:build
bin/dev
```

Then sign in with:

- Email: `admin@admin.com`
- Password: `Password`

Useful routes:

- `/` - dummy app demo with seeded folders, pages, cards, message groups, and access results
- `/message_groups` - dummy app demo of message groups under shared `MessageRoot`, first owner via bootstrap
- `/recording_studio_accessible` - addon status/demo page
- `/recording_studio_accessible/recordings/:recording_id/accesses` - gem-provided page for managing direct recording access and pending invitations
- `/invitation_signups/:token/new` - dummy signup page that creates the invited user and accepts the invitation

The demo seeds:

- one workspace root recording, first owner via `bootstrap_owner_access!`
- folders and pages as recordable demo content
- cards attached to seeded pages
- a shared `MessageRoot` with an accessible `MessageGroup`; first owner via bootstrap, later workspace grant via `grant_access`
- multiple users with root, folder, page, and no-access states

That makes it obvious that the access feature is appearing because this addon is installed alongside RecordingStudio.

## Cloud Agent boot

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
The install hook provisions a cold image. On a warm snapshot it skips apt,
ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
already usable. Fetch-skills always runs last. `.cursor/start.sh` starts
PostgreSQL on each boot. Rebuild with Draft off to load a new pack. See
[Cursor skills in Cloud Agents](docs/cursor-skills.md).

## Running tests

From the repository root:

```bash
bundle exec rake test
bundle exec rake app:test
bundle exec rubocop
```

If dummy app boot, assets, or migrations change, also run:

```bash
cd test/dummy
bin/rails db:migrate RAILS_ENV=test
bin/rails tailwindcss:build
```

## Documentation

The original template architecture docs remain in `docs/gem_template/` as reference material.
