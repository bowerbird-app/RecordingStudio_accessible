# Recording Studio Accessible

Recording Studio Accessible is the optional access-control addon for `RecordingStudio`.

It extracts the access-specific pieces that currently live in RecordingStudio core into a standalone engine so host apps can install access behavior intentionally instead of assuming it is always present.

## What the gem provides

- child-only `RecordingStudio::Access` recordables for direct grants under opted-in recordings
- optional dependent grants: one Access recording can be capped by and die with another Access recording on the same root. Dependents void in place when the manager Access is revised weaker, trashed, destroyed, or moved — they do not follow a move
- optional per-action audiences (`public`, `signed_in`, `granted`, plus `register_audience`) with workspace limits and per-recording rules
- `RecordingStudioAccessible.role_for`, `actors_with_access`, `role_through`, `authorized?`, `authorized_through?`, and `authorized_action?` for role lookup, grants, and named-action checks
- a mounted engine for adding, updating, and removing direct access on a recording, plus workspace-scoped actor access-point pages
- Recording Studio API member actions (`list_access`, `grant_access`,
  `update_access`, `revoke_access`) that wrap the same grant path, when
  `recording_studio_api` is loaded
- `RecordingStudioAccessible::ControllerAuth` for sibling addon engines that share authenticate / authorize / current-root helpers
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
gem "recording_studio", "~> 6.1", ">= 6.14.0"
gem "recording_studio_accessible"
# Query-only trash helpers used by Accessible (pin by tag or host equivalent).
# Prefer require: false; Accessible loads recording_studio_trashable/query,
# which registers the :trashable recording filter.
gem "recording_studio_trashable", "~> 0.10", ">= 0.16.0", require: false
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

Accessible loads Trashable’s query entry point only
(`require "recording_studio_trashable/query"`). That file registers Trashable’s
`:trashable` recording filter. Relation filters use `Recording.kept`. Raw and
joined SQL uses `RecordingStudio.kept_sql(alias)`. Both match every recording
until a filter is registered. In-memory grant checks call
`recording_studio_trashable_kept?` when the object responds to it; otherwise
the object counts as kept. Accessible does not load the Trashable
engine/importmap or the `:trashable` capability, and it does not soft-void
Access grants; revoke and dependent cleanup still destroy those rows. Hosts
that want the trash UI install and mount Trashable separately.

If you want the gem-provided mounted UI for managing direct access, then also run:

```bash
bin/rails generate recording_studio_accessible:access_management --link-helper
```

`recording_studio_accessible:install` is the base setup step. It copies the
initializer and share-email templates, and it can optionally add
`config/recording_studio_accessible.yml` for simple environment-specific
settings such as `warn_on_core_conflict`. Proc-based hooks still belong in the
initializer.

## Configuration

Host apps still configure `RecordingStudioAccessible::Configuration` through
`RecordingStudioAccessible.configure`. The class lives in
`lib/recording_studio_accessible/configuration.rb`; focused mixins under
`lib/recording_studio_accessible/configuration/` hold avatars, actors,
authorizers, invitations, and mail defaults.

`config.layout` chooses the layout for engine screens. Leave it unset and
the screens use `RecordingStudio.configuration.layout`, then
`recording_studio/default_layout`.

```ruby
RecordingStudio.configure do |config|
  config.layout = "admin"
end

RecordingStudioAccessible.configure do |config|
  config.layout = "admin"
  # config.layout = ->(controller:) { "admin" }
  # config.layout = false
end
```

A callable receives `controller:` and returns a layout name, `nil`, or
`false`. It runs when the screen renders, after authentication and access
checks. A denied actor stays denied when the callable raises. `false` renders
the screen with no document layout. Access-request modal frames still render
without a document layout, and they do not call the layout callable.

## Controller auth for sibling engines

Sibling Recording Studio gems often copy the same ApplicationController auth
helpers. Use `RecordingStudioAccessible::ControllerAuth` instead of duplicating
them.

```ruby
module RecordingStudioX
  class ApplicationController < ActionController::Base
    include RecordingStudioAccessible::ControllerAuth

    recording_studio_auth(
      config: -> { RecordingStudioX.configuration },
      prefix: :x
    )
  end
end
```

The macro:

1. Adds `before_action :authenticate_x_actor!` and `before_action :set_x_current_actor` (unless turned off)
2. Defines **private** one-line helpers so Rails `action_methods` stays clean and host overrides keep working:
   - `authenticate_x_actor!` → `authenticate_recording_studio_actor!`
   - `x_actor` → `recording_studio_actor`
   - `current_x_root` → `current_recording_studio_root` (also a `helper_method`)
   - `set_x_current_actor` → `set_recording_studio_current_actor`

`prefix` must match `/\A[a-z_][a-z0-9_]*\z/`. Calling the macro twice on the same
controller raises. Options are frozen. Auth class attributes are class-only readers.

Shared methods (defaults match the presskits ApplicationController):

| Method | Behavior |
| --- | --- |
| `authenticate_recording_studio_actor!` | Calls `config.authentication_method` when present; otherwise `head :unauthorized` |
| `recording_studio_actor` | `Current.actor.presence`, else `config.current_actor_method` |
| `authorize_recording!(recording, role:)` | `head :unauthorized` with no actor; `head :forbidden` unless `recording` and `RecordingStudioAccessible.authorized?` |
| `current_recording_studio_root` | `current_root_recording` when the controller responds to it |
| `require_root!` | `head :forbidden` when no root |

When the configured `authentication_method` is not defined on the controller, Accessible logs a `Rails.logger.warn` naming the missing method and still responds `:unauthorized`.

When a gem’s previous behavior differed, pass options instead of changing defaults:

```ruby
# brands-like
recording_studio_auth(
  config: -> { RecordingStudioBrands.configuration },
  prefix: :brands,
  set_current_actor: false,
  actor_resolution: :method_only,
  missing_actor_status: :forbidden
)

# site_settings-like names + configured method result as-is (nil stays nil)
recording_studio_auth(
  config: -> { RecordingStudioAdmin.configuration },
  prefix: :site_settings,
  authenticate_method: :authenticate_recording_studio_site_settings!,
  set_current_actor_method: :set_current_actor,
  actor_method: :current_actor,
  actor_resolution: :configured_as_is
)

# stripe-like
recording_studio_auth(
  config: -> { RecordingStudioStripe.configuration },
  prefix: :stripe,
  authenticate: false,
  set_current_actor: false,
  require_actor: true,
  actor_resolver: -> { /* … */ },
  root_resolver: -> { /* … */ },
  on_missing_actor_for_root: -> { redirect_to sign_in_path, alert: "…" },
  missing_root_status: :not_found,
  response_style: :plain,
  plain_bodies: { missing_root: "pick a workspace" }
)
```

The configuration object only needs `authentication_method` and
`current_actor_method` unless you pass `actor_resolver` / `root_resolver`.
Accessible gains no new gem dependencies for this concern.

### Why Accessible keeps an authentication hook

Sign-in normally belongs to Recording Studio Users (`recording_studio_user`).
`ControllerAuth`’s host-configured `authentication_method` is the one approved
exception: Users already depends on Accessible for permissions
(`RecordingStudioUser::ProfileAccess`), so Accessible cannot depend on Users
without a circular gem dependency.

Hosts should leave authentication in Users (Devise) and point the Accessible
config hook at that API — for example `authenticate_user!` — rather than
re-implementing sign-in inside Accessible:

```ruby
# In the host or addon configuration used by recording_studio_auth
config.authentication_method = :authenticate_user!
config.current_actor_method = :current_user
```

Accessible still owns permission checks (`authorize_recording!`, root helpers,
`RecordingStudioAccessible.authorized?`). It does not resolve sign-in itself.

## Access requests

Someone without access can ask for a role. The request is a child recording
on the target, `RecordingStudio::AccessRequest`. Writes go through:

```ruby
RecordingStudioAccessible.request_access(recording:, actor:, role:, action: nil, message: nil, controller: nil)
RecordingStudioAccessible.transition_access_request(
  request_recording:, status:, manager_actor:, role: nil, review_note: nil, controller: nil
)
RecordingStudioAccessible.approve_access_request(request_recording:, manager_actor:, role:, controller: nil)
RecordingStudioAccessible.deny_access_request(request_recording:, manager_actor:, review_note: nil, controller: nil)
```

`transition_access_request` is the state machine. A manager can move a request
from pending, approved, or denied to either of the other two. The same move
revises the snapshot and appends `approved`, `denied`, or `reopened`.
Approving calls `grant_access` with the chosen role, stores that grant on the
request, sends the access-granted email, and runs `:access_request_approved`.
Denying runs `:access_request_denied`. It also calls
`config.access_request_denied_notifier` when one is set. Moving away from
approved revokes the grant that approval created. Moving back to pending
clears the role, the review note, and the grant id, and runs
`:access_request_reopened`. Submit and re-submit still append
`access_request_submitted` and `resubmitted`. Revoking the grant on its own
does not rewrite the request.

One open request per person and target. Asking again revises that request.
A partial unique index on the live pending row enforces the same limit in the database.
A person who already has the role gets a no-op success.

The email-code screens use Recording Studio Users `request_otp!`. A throttled
result shows the rate-limit message. An issued result and a suppressed result
both show the same code page. `verify_otp!` and `complete_email_proof!` finish
the proof. The email step collects a name and passes `first_name` and
`last_name` into `complete_email_proof!`, the same way Messages does for
public contact. The field is required when the user model validates `name` or
`first_name`, and optional otherwise. Accessible cannot list Users as a gem
dependency, because Users already depends on Accessible. Add Users in the host
app, with OTP enabled. Signed-in actors can call `request_access` without that
stack.

One-time codes count through `Rails.cache`. The store has to be shared and
atomic across processes. Redis or Memcached is that store. The dummy test and
development environments use an in-process memory store. Its increments are
atomic inside one process, which is enough for the test suite, and they do
not enforce the limit across processes. The host users table needs a
case-insensitive unique index on `email`. A unique index on `LOWER(email)`
is the usual shape.

Routes live under the mounted engine:

```
/recordings/:recording_id/access_requests/new
/recordings/:recording_id/access_requests
/recordings/:recording_id/access_requests/:id
/access_requests
```

### Access request index

The manager list is one slice. Mount it on a single recording, or across many.
Both routes render it. A host page can render the same partial.

```erb
<%= access_requests_index(recordings: press_kit) %>
<%= access_requests_index(recordings: press_kits, url: press_kit_requests_path) %>
```

`recordings` is one recording or a relation of them. A row is included only
when `AccessManagementPolicy` allows its parent. The default authorizer is
effective admin: a kept grant on that parent, an ancestor, or its root. The
index finds those parents in SQL, then pages the requests. A replaced
`access_management_authorizer` is still called for each parent. The
collection route uses `config.access_request_index_recordings` when it is
set, and otherwise every recording that already has a request.

```ruby
config.access_request_index_recordings = ->(actor:, controller:) { press_kits }
```

`url` is where the status filters and the next page return. It should render
this helper again. The filters are Flatpack pills. The active one is the grey
pill. Pending is the default, and a pending row uses the primary badge.
Approved and denied rows use the default badge.
`status` is `pending`, `approved`, `denied`, or `all`. A long list appends the
next page with Flatpack infinite scroll. The cursor is the last row's time and
id. The page size is 10.

The name column shows the requester's name, from the profile collected at the
email step or already on the user record, with the email underneath. A person
with no name is shown by email alone. The list has no note column. A single
recording hides the recording column. More than one shows the recording's name
or title, linked when the host can route to that recordable. The name links to
the request page. Every row has a Review button. Review opens that same request
page in a modal: the heading, the date, the quoted message, any gate answers,
and the Approve and Deny tabs. The Approve tab submits with Approve. The Deny
tab submits with Deny. A save from the modal returns to the list and keeps the
filter. A save from the full request page stays on that page. A list rendered
on the collection route returns there. Any other list URL returns to that
recording's request list.

`new` is the email step, the code step, or the request form. The email step
shows the recording's name or title under the heading. Later steps do not.
Visitors do not pick a role. Pass an optional `role:` or `action:` when the
caller already knows a suggestion. The request page heading names who asked
and which recording. The date they asked is the subtitle under that heading.
The message stays on the page, in quotes. Gate
answers are labelled rows, flush with that heading. A manager uses Approve
and Deny underline tabs. Approve lists the allowed roles as inline radios with icons.
Deny has an
optional note. The Approve tab submits with Approve, and the Deny tab submits
with Deny, both through `transition_access_request`. An
approved request opens on Approve, and a denied request opens on Deny. The
role choice defaults to the suggestion when it is allowed, then to the
action's granted roles, then to `roles_for`. Events stay on the recordable.
The page does not list them.

The email, code, and request steps, and the request page, each render as a
full page and inside the `access_request` Turbo frame. Pass
`presentation=modal` and load that frame to use the modal. Open access-request
modals hide before Turbo caches the page, so Back/Forward does not restore a
stale dialog.

Visitor copy defaults to `recording_studio.accessible.requests`. Override one
flow with `copy:` or an I18n `scope:`. Scope keys match the relative request
keys, such as `cta` and `email_title`. A missing key falls back to the default.
The overrides follow every step of that flow.

```erb
<%= access_request_modal(recording, copy: {
  cta: "Request early access",
  email_title: "Request early access",
  form_title: "Ask for early access"
}) %>
<%= access_request_modal(recording, scope: "press_kit.early_access", role: "view") %>
```

`label:` still sets the button when `copy[:cta]` is absent.

### Access request gate

A host can pause the request until its own step is done. Accessible does not know the question. An action with no registered gate uses the gate registered under `:default`, including a blank action. When that gate is missing too, the step is skipped. A raise still fails closed on the form and on create.

```ruby
RecordingStudioAccessible.configure do |config|
  config.register_access_request_gate(:read, Presskits::AccessRequestGate)
  config.register_access_request_gate(:default, Presskits::AccessRequestGate)
end
```

Register a class or any object. Every method is optional:

| Method | Role |
| --- | --- |
| `satisfied?(recording:, actor:, request:)` | `true` when the host step is done. Omit it and the gate does not block. A raise fails closed. |
| `continuation_url(recording:, actor:, request:)` | Where the visitor goes while the gate is still open. Same host only. A modal keeps `presentation=modal` and the `access_request` frame. |
| `component` | Optional ViewComponent class. Accessible does not render it; the continuation page is the form. |
| `metadata_for(recording:, actor:)` | Flat hash copied onto the request when it is submitted or submitted again. |
| `metadata_labels` | Optional key to label hash for the manager review list. |

The check runs after the email code, and again for a signed-in visitor opening the form. `create` checks `satisfied?` again before it writes. While the gate is open, the visitor is redirected to `continuation_url` with the presentation params. A modal redirect stays in the `access_request` Turbo frame. A full page redirect stays a full page.

A continuation URL on another host is not followed. If `satisfied?` or `continuation_url` raises, or the URL is missing, the visitor sees a Flatpack alert and the request is not recorded.

In-progress answers stay with the host. Accessible does not open a draft row for them.

`gate_metadata` is `jsonb`, default `{}`, with no GIN index. Submit and re-submit keep a flat snapshot on that version of the recordable, so it stays with the history:

- at most 32 keys
- each key matches `[a-z0-9_]{1,40}`
- values are scalars: string, number, boolean, or null
- strings at most 200 characters
- the JSON document at most 2KB

Dropped data is reported. A metadata failure stores `{}` and the request still proceeds when the gate is satisfied. Accessible does not interpret the keys.

Managers who pass `AccessManagementPolicy` see the answers as a read-only labelled list beside the note. Labels come from `metadata_labels` when the gate provides them, otherwise the key is humanized. The requester does not see that list.

Locked screens:

```erb
<%= access_request_modal(recording, role: "view", action: "read") %>
<%= link_to "Request access on a page", access_request_page_path(recording, role: "view", action: "read") %>
```

Hooks: `:access_request_submitted`, `:access_request_approved`,
`:access_request_denied`, `:access_request_reopened`. Approval sends the
access-granted email. Denial sends mail only when
`config.access_request_denied_notifier` is set. A submitted
request emails direct admins on the target and its parents. Replace that with
`config.access_request_submitted_notifier`.

## Compatibility with RecordingStudio 6.1

Recording Studio Accessible targets RecordingStudio `~> 6.1`, `>= 6.14.0` (currently
tested with `v6.14.0`) and Trashable `~> 0.10`, `>= 0.16.0` (currently tested
with `v0.16.0`). It uses Recording Studio's capability-owned child recordable
contract. RecordingStudio
core no longer ships built-in access control, so this addon provides
`RecordingStudio::Access` and `RecordingStudio::AccessRequest`, declares them
as child-only recordables, and registers them as metadata for the `:accessible`
capability.

On load, the addon registers:

```ruby
RecordingStudio.register_capability(
  :accessible,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access", "RecordingStudio::AccessRequest"]
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

#### Upgrading to 0.41.0

No migration. `authorized?` is unchanged. `authorized_recording_ids(actor:, root:, role: :view, recordable_type: nil)` returns an unloaded one-column relation of recording ids under that root that `authorized?` allows. A custom authorization service must implement `authorized_recording_ids`, or callers keep using `authorized?`. `authorized_recording_ids_supported?` is false when the configured service does not implement the query, and calling it raises.

#### Upgrading to 0.40.0

No Accessible migration. Install Recording Studio `~> 6.1`, `>= 6.13.0`. Dependent voiding still writes one deleted event per grant, in void order, and still rolls the batch back. Those events go through `RecordingStudio.record_events!` and store `root_recording_id`. Hosts that have not run Recording Studio's `root_recording_id` migration on `recording_studio_events` need that core migration. Recording Studio 6.13.0 adds no migration of its own.

#### Upgrading to 0.39.0

No migration. `root_recordings_for` and `root_recording_ids_for` are unchanged. `authorized_root_recording_ids(actor:, role: :view)` returns a one-column relation of root recording ids that `authorized?` allows on that root. A custom authorization service must implement `authorized_root_recording_ids`, or callers keep using `authorized?`. `authorized_root_recording_ids_supported?` is false when the configured service does not implement the query, and calling it raises.

#### Upgrading to 0.38.0

No migration and no caller change. `effective_audience` and `authorized_action?` still take one recording. Audience checks load that root's rules and constraints once and reuse the query cache until a write clears it. Allow and deny stay the same.

#### Upgrading to 0.37.0

No migration and no caller change. Dependent voiding writes one deleted event per grant, then destroys the grant. Last-admin is checked once per parent. A void that would remove the last admin still rolls back the whole batch.

#### Upgrading to 0.36.0

Breaking. `access_management_actor_scope` no longer defaults to every user. Manage access and actor-id grants raise `RecordingStudioAccessible::ConfigurationError` until the host sets a scoped lookup. `authorized?` and `role_for` are unchanged. Add:

```ruby
config.access_management_actor_scope = ->(_controller) { User.order(:email) }
```

Duplicate access repair, dependent voiding, and audience narrowing keep the same allow and deny results.

#### Upgrading to 0.35.0

No migration and no caller change. Effective roles are unchanged.

`recordings_for` loads the actor's grants on the shared ancestor path once, the grants on every candidate child once, and the audience rules and constraints for those children once. Each child still uses the same role precedence as `role_for`. The children that stay are unchanged. A public audience still does not list a child with no grant.

Manage access, the avatar rollup, and the last-admin check read one preloaded grant set. Actors load per type, and each actor's effective role is computed once. Inside a locked revoke or role change, `LastAdminGuard` keeps that lookup and reads grants again after the write, with the query cache off.

#### Upgrading to 0.34.0

No migration. The access-request index still uses the same page size and the same people can see a request.

The index finds parents the actor administers in SQL, then pages those requests. The default authorizer is still effective admin on the parent, an ancestor, or the root. A custom `access_management_authorizer` is still called for each parent.

`root_recordings_for` and `root_recording_ids_for` apply the dependent-grant check in SQL. The roots are the same set as before. Callers do not need to change.

Hosts on Recording Studio 6.5+ need `config.authorize_write`, or `config.allow_unauthorized_writes` when writes happen with no actor. Install Trashable `0.14.0`'s `purge_at` migration and restamp existing trash with `bin/rails recording_studio_trashable:restamp_purge_at`.

#### Upgrading to 0.33.0

No migration.

`RecordingStudioAccessible.actors_with_access(recording:, minimum_role: :view)` lists each actor who has an effective role on that recording, with that role. It follows the same path and rules as `role_for`. It does not include invitations or audience gates (`public`, `signed_in`).

`list_access` still returns direct grants, inherited grants, and pending invitations. A direct or inherited grant that is not effective (a dependent whose manager is missing, trashed, off-root, or weaker) is left out. If that actor still has an effective grant on an ancestor, the inherited row remains.

#### Upgrading to 0.32.0

No migration.

`grant_access` with `actor_id` now defaults `actor_type` to `User` when `User` is in `access_actor_types`, the same default `update_access` and `revoke_access` already used. If `User` is not allowed, `actor_type` is still required. Demoting the last admin returns `errors.last_admin_role_change` ("Add another admin before changing the last admin's role."). Revoke still uses `errors.last_admin`. Hosts can set per-type OpenAPI title and description with `RecordingStudioAccessible::Api.override_openapi(type:, action:, title:, description:)`; other types keep the generic Accessible copy. The four access actions now document real 200 schemas for the payloads they already return.

#### Upgrading to 0.31.0

No migration.

`list_access` `grants` now includes unclosed email invitations (`status: pending` or `expired`) from `AccessInvitation.pending_rows_for`. Those rows have `email` and `role`, not `actor`. Direct and inherited grants use `status: granted`. Filter `status: granted` if you still want accepted grants alone. `grant_access` and `update_access` describe default roles from `RoleSet::DEFAULT_NAMES`; validation stays on `role_valid_for?`. See 0.32.0 for the User default on `grant_access` `actor_type` and per-type OpenAPI overrides.

#### Upgrading to 0.30.0

No migration.

`before_access_grant` also runs before the new-access page (`source: :new_access`) and the invitation page (`source: :new_invitation`). On new access, `role` and the grantee (`actor`) are nil and `granted_by` is the current actor. On the invitation page, `actor` is the signed-in invitee, `role` is the invitation role, and `granted_by` is the inviter. Leave the config unset and those pages stay as they are.

#### Upgrading to 0.22.0

No migration.

1. Install Accessible `0.22.0` with Recording Studio `~> 6.1`, `>= 6.1.0` (this repo tests `v6.1.0`) and Flatpack `0.1.319`. Trashable stays `recording_studio_trashable ~> 0.10`. Do not add `recording_studio_user` to the Accessible gemspec.
2. Leave `config.layout` unset to use `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`. Set the Accessible layout only when these screens should differ from the core layout. A callable is `->(controller:) { "name" }` and returns a layout name, `nil`, or `false`.
3. Delete host copies of `recording_studio_accessible/blank` and `recording_studio_accessible/access_request`. Page titles belong in `content_for :title` and `content_for :subtitle`. Close and back belong in `flat_pack_page_nav`. `FlatPack::Card` no longer accepts `style:`.
4. Access-request modal frames still have no document layout. A denied actor still fails closed before a layout callable runs.
5. Manage access shows `+ Access` and `Access requests` in the top-right ButtonGroup overflow. A host layout must render `:page_nav_right`. Pending access requests on that recording add a count on `Access requests`.

#### Upgrading to 0.21.0

No migration. `recording_studio_accessible_avatars` is unchanged.

1. Install Accessible `0.21.0`.
2. To put access inside a Flatpack dropdown, call `recording_studio_accessible_access_menu_item` from the dropdown block. The label comes from `recording_studio.accessible.manage.access_menu` (`Access`). Pass `label:` to override that one item. `scope:` matches the avatar helper (`:direct` by default, or `:all` for inherited people too).
3. Host locale files that mirror the gem keys need `manage.access_menu`. Missing keys still fall back to English.
4. The menu row shows a count badge. Flatpack's menu item has no avatar slot, so the faces stay on `recording_studio_accessible_avatars`.

#### Upgrading to 0.20.1

No migration.

1. Install Accessible `0.20.1` with RecordingStudio `~> 4.7, >= 4.7.1` (this repo tests `4.7.1`) and Flatpack `0.1.275`. Trashable stays `recording_studio_trashable ~> 0.10`. Do not add `recording_studio_user` to the Accessible gemspec.
2. If you override an engine page nav view, replace the old PageNav keywords with `with_back`, `with_link`, `with_close`, `with_action`, or `with_item`. Flatpack 0.1.274 removed the old keywords and they raise. Close and back hrefs must be a known route or a validated same-origin path.
3. Leave `config.layout` unset to keep the current layouts. Set it only when engine screens should render inside a host layout.
4. Update assertions on the old screen labels. The manage-access primary button is `+ Access`. The new-access title is `Share access` and the submit button is `Give access`. The role field is still `access[role]`.

#### Upgrading to 0.20.0

Access requests are new. Run the migrations.

1. Install Accessible `0.20.0`.
2. Copy the migrations and run them.

```bash
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

3. New tables are `recording_studio_access_requests` and `recording_studio_access_request_intents`. `gate_metadata` is added to `recording_studio_access_requests`.
4. Accessible does not depend on Users in the gemspec. Hosts that want the email-code screens add `recording_studio_user` the same way Messages does. Without Users, `request_access` still works for a signed-in actor.

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

#### Upgrading to 0.17.0

Accessible now depends on Recording Studio Trashable `~> 0.10` and loads only
`recording_studio_trashable/query` for kept/trashed helpers.

1. Install Accessible `0.17.0` and resolve `recording_studio_trashable` `~> 0.10`
   (git tag `v0.10.0` or host equivalent), preferably with `require: false`.
2. No Accessible migration. Keep your existing `trashed_at` column if present.
3. Revoke and dependent void still hard-destroy Access recordings; they do not
   call `RecordingStudioTrashable.void_recording!`.
4. Accessible does not mount Trashable UI or register trash importmap pins.

#### Upgrading to 0.19.0

This is a minor upgrade. Default English interface text is unchanged.
Requires RecordingStudio `~> 4.7`. Gem-shipped
`recording_studio.accessible.*` keys fall back when the active locale has no
translation via `RecordingStudio.t`: loaded `:en` (host English overrides
included), then the caller's `default:`, then the merged shipped-English table
(this gem registers `config/locales/en.yml` at boot).

1. Install Accessible `0.19.0` and RecordingStudio `~> 4.7`. No migration.
   English hosts need no change.
2. Prefer `RecordingStudio.t` / `Copy.t` / `accessible_t` for gem keys so
   missing locales keep the same fallback (no hand-copied English `default:`
   strings that can drift from `en.yml`).
3. Hosts that set raise-on-missing translations will no longer raise for
   gem-shipped keys resolved through those helpers when the active locale lacks
   the key. Host overrides in the active locale still win.
4. A missing `_html` key with a caller `default:` now follows
   `RecordingStudio.t` / view `t` escaping (args escaped, template markup kept)
   instead of main's `Copy.t` whole-template escaping. No in-gem call site does
   this.
5. Public message constants remain for API compatibility; displayed copy no
   longer passes them as `default:`.

#### Upgrading to 0.15.0

Wave 2 finishes host-overridable copy outside views: HomeController demo titles/status bodies, call-time recordable labels, and remaining user-facing validation/service errors.

1. Install Accessible `0.15.0`. No migration.
2. Copy new `recording_studio.accessible.home.methods.*`, `home.user_invites.statuses.*`, `home.user_invites.setup.*`, `recordables.*`, and `errors.*` keys into host locale files when translating.
3. Public message constants and recordable `LABEL`s stay for API compatibility; displayed copy uses `Copy.t` (English fallback from 0.19.0).
4. `recording_studio_recordable label:` stays English (class-load DSL). Ruby code samples on demo pages, generator CLI text, and developer `ArgumentError`s stay English.

#### Upgrading to 0.13.0

Actor access points and the engine demo/docs home pages now use Rails I18n under `recording_studio.accessible.actor_access_points.*` and `recording_studio.accessible.home.*`. English output is unchanged.

1. Install Accessible `0.13.0`. No migration.
2. Copy the new keys into host locale files when you translate those screens.
3. Generator text and developer `ArgumentError`s stay English. HomeController demo titles/status copy moved to I18n in 0.15.0.

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
`authorized_root_recording_ids` follows `authorized?` on the root, so a shared
root stays in that relation when a kept grant sits on the shared root itself.
`authorized_recording_ids` follows `authorized?` for every recording under the
root you pass. A legacy grant on the shared root covers that root and its
descendants. A grant only on a child leaves the shared root out and covers
that child and its descendants.
`recordings_for` still lists direct children of a shared-root parent. See
[Children under one parent](#children-under-one-parent).

Useful RecordingStudio 4 introspection helpers:

```ruby
RecordingStudio.capability_child_recordables_for(:accessible)
# => ["RecordingStudio::Access", "RecordingStudio::AccessRequest"]

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

RecordingStudioAccessible.update_access(
  recording: recording,
  access_recording: access_recording,
  role: :edit,
  manager_actor: current_actor
)

RecordingStudioAccessible.revoke_access(
  recording: recording,
  access_recording: access_recording,
  manager_actor: current_actor
)
```

A recording that already has an effective admin cannot be taken to zero
admins by `revoke_access`, by `update_access` that drops the role below
admin, or by the dependent-grant void cascade. Effective admin is a kept,
ranked `:admin` grant on that recording or an ancestor. Pending invitations,
trashed grants, and dependents whose manager is invalid do not count. The
failure is `RecordingStudioAccessible::LastAdminError` (copy key
`recording_studio.accessible.errors.last_admin`). The manage-access UI
flashes that message. See `docs/screenshots/last-admin-flash.png`. API
`update_access` and `revoke_access` return 422.

Self-removal is allowed when another effective admin remains. Invitation
revoke is never blocked. Destroying the recording is not guarded.

Teardown and staff scripts can pass `allow_last_admin_removal: true` on
`revoke_access` and `update_access`. That flag is passed through to
`VoidDependentAccesses`.

`actor` is the polymorphic object receiving access. It can be a user,
workspace, company, team, system actor, or another configured access actor.
`manager_actor` remains the actor performing the access-management action.

A grant may also depend on another Access recording on the same root. The
dependent role cannot exceed that manager grant's role, and
`authorized?` / `role_for` fail closed if the manager Access is later
trashed, destroyed, off-root, or downgraded. `root_recordings_for` and
`root_recording_ids_for` use that same chain. A root is listed only when
the actor has an independent grant, or a dependent grant whose every
manager hop is still a kept Access recording on the same root, with a
ranked role at least as strong, and the chain does not cycle. Audience
limits do not add or remove roots. `authorized_root_recording_ids` uses that
same chain for grants whose parent is the root, and those ids match
`authorized?` on each root. See [Root ids for one actor](#root-ids-for-one-actor).
`authorized_recording_ids` uses that same chain for grants anywhere under the
root you pass. See [Recording ids under one root](#recording-ids-under-one-root).
A background void job then
destroys the dependent grant in place. The job writes one deleted event per
grant, on that grant's parent, then destroys the grant. Last-admin is checked
once for each parent. A void that would remove the last admin rolls back the
whole batch, including those events. If the manager Access recording is
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

### Refusing a grant from the host

Set `config.before_access_grant` when the host must refuse a grant the gem
would otherwise write. Featured In uses this for a plan seat cap. This gem
does not know about plans, seats, Stripe, or teams.

The callable receives one frozen `GrantContext` (`actor`, `actor_type`,
`actor_id`, `recording`, `role`, `previous_role`, `source`, `granted_by`).
`source` is `:grant`, `:role_change`, `:invite`, `:invite_acceptance`,
`:access_request`, or `:bootstrap`. Return to allow. Raise
`RecordingStudioAccessible::GrantRefused` to refuse. Pass optional
`redirect_to` (a host path or URL such as `/plans`). Manage access then
sends the manager to that page with the message in `flash[:alert]`. Omit
it and the current page shows the alert only. Other exceptions are not
converted into a refusal.

The hook runs inside `AccessGrantWriter#upsert_access_recording!`, in the
write transaction, after the recording lock and after the built-in checks
(valid role, placement, duplicate handling, last-admin on role change).
`grant_access`, `update_access`, invite acceptance, and access-request
approval share that path. A host that counts direct grants on the locked
recording is race-safe with other writers.

Invite creation also runs the hook with `source: :invite` so a pending
invite can fail early. Acceptance is the authoritative write.

The new-access page calls the same hook after the manage-access check,
with `source: :new_access`. `role` is nil, `actor` (the grantee) is nil,
and `granted_by` is the current actor. The invitation page calls it after
the signed-in check, with `source: :new_invitation`. `actor` is the
signed-in invitee, `role` is the invitation role, and `granted_by` is the
inviter. That matches an `:invite_acceptance` write.
`GrantRefused` redirects or shows the alert the same way a refused write
does. Any other error does not render the form. The write still runs the
hook, so a direct POST is refused even when the page was shown.

`bootstrap_owner_access!` writes through `create_access_recording` after its
own lock. It does not call `before_access_grant`. A new workspace's first
owner is never blocked by this hook.

The manage-access screens do not show a gate button. Screenshots of Share
access with no gate UI: `docs/screenshots/grant-refused-share-390.png` and
`docs/screenshots/grant-refused-share-1280.png`. The dummy `/plans` flash:
`docs/screenshots/grant-refused-plans-390.png` and
`docs/screenshots/grant-refused-plans-1280.png`.

Default is `nil`. Existing hosts keep current behaviour.

```ruby
RecordingStudioAccessible.configure do |config|
  config.before_access_grant = lambda do |context|
    next if context.previous_role.present?

    root = RecordingStudio.root_recording_or_self(context.recording)
    next unless root == context.recording

    cap = 5
    count = RecordingStudioAccessible.access_recordings_for(root).count
    next if count < cap

    raise RecordingStudioAccessible::GrantRefused.new(
      "You've filled every seat. Free one up, or pick a larger plan.",
      redirect_to: "/plans"
    )
  end
end
```

Count the actor on the grant. Grants can target any allowlisted actor type,
including a Workspace in this dummy. There is no separate Group or Team
grant type in this gem. If the host grants a workspace (or another
non-user actor), the hook sees that actor, not its members.

Audience rules and access-point pages do not create Access grants. Access
requests create a request row. Approval writes through
`AccessGrantWriter` and is covered.

`AccessCreationContext.allow` is an integrity gate around writing an
Access recordable, not a product grant API. Call sites: create and
revise in `AccessGrantWriter` (hook already ran), and
`AccessGrantIntegrity` repair (not a product grant, so the hook does
not run). Do not grant through that context yourself.

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

Manage access, and API grants that pass `actor_id`, also need
`access_management_actor_scope`. That lookup is the list of people the screen
may grant. Set it to a scoped relation. There is no default. An unset scope
raises `RecordingStudioAccessible::ConfigurationError` instead of listing every
user.

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_management_actor_scope = lambda do |_controller|
    User.order(:email)
  end
end
```

Narrow that relation to the actors the current person is allowed to grant.
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

Those pages use the Recording Studio default layout unless you set
`config.layout`, render FlatPack-based UI, and let authorized
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

Manage access lists each person as a Flatpack list item: a photo or user
icon in the leading slot, name as the title, role on the subtitle, and
the access actions dropdown as the trailing control. The subtitle does
not repeat the email. Pending, expired, actor type, and inherited source
stay on that line. Pending invitations always use the icon. Screenshots: `docs/screenshots/manage-access-index-390.png`
(phone), `docs/screenshots/manage-access-index-390-actions.png` (actions
menu open), and `docs/screenshots/manage-access-index-1280.png` (desktop).

`+ Access` and `Access requests` sit in the top-right outlined ButtonGroup
overflow at every width. A pending count is appended to the Access requests
label. The group does not use `collapse: :menu`. A host layout must render
`:page_nav_right`.

`AccessInvitation` records pending intent for an email address. `RecordingStudio::Access` records authorization for a persisted actor. `authorized?` and `role_for` read access grants only.

`invite_access` calls `grant_access` when the email already belongs to an actor. Otherwise it stores one unclosed `AccessInvitation` for that recording and email. Unclosed means not accepted and not revoked. An expired invitation stays in that slot, and a later invite refreshes the same row instead of inserting another one. After the invited person authenticates, `accept_access_invitation` calls `grant_access` and stamps the invitation accepted. `revoke_access_invitation` withdraws a pending invitation and leaves any access grant alone.

### Access management over Recording Studio API

The same manage-access path is available as member capability actions when
Recording Studio API is loaded. Accessible registers them from an engine
initializer (`before: "recording_studio_api.after_initialize"`). It does not
add a runtime gemspec dependency on `recording_studio_api`.

| Action | Inputs | Result |
| --- | --- | --- |
| `list_access` | none | `{ grants: [...] }` with `status` (`granted`, `pending`, or `expired`). Granted rows include actor (`id`, `type`, `label`), `role`, `source_recording` (`id`, `type`, `label`), `inherited`, and `effective_role`. Pending invitation rows include `email`, `role`, and `source_recording`. |
| `grant_access` | `email` plus `role`, or `actor_id` plus `role` (`actor_type` defaults to User when User is allowed). `role` describes `RoleSet::DEFAULT_NAMES`; types may declare others | granted row, or `{ invited: true, email, role, notice }` |
| `update_access` | `actor_id`, `role`, optional `actor_type`. Same `role` description as `grant_access` | updated direct grant |
| `revoke_access` | `actor_id`, optional `actor_type` | `{ revoked: true, actor }` |

Email is the people path and matches the manage-access form (`invite_access`).
`actor_id` grants, updates, and revokes default `actor_type` to `User` when
`User` is in `access_actor_types`. Otherwise `actor_type` is required. Grants
are limited to the types returned by `access_management_actor_scope`
(`grantable_actors_for`). Do not mix `email` with `actor_id`.
`update_access` and `revoke_access` change or remove a direct grant for that
actor on this recording. They refuse inherited grants; change the source
recording instead. They also refuse a write that would remove the last
effective admin (HTTP 422). Revoke uses
`recording_studio.accessible.errors.last_admin`. A last-admin role change uses
`errors.last_admin_role_change`.

Host gems can override OpenAPI title and description for one recordable type
without changing other types:

```ruby
RecordingStudioAccessible::Api.override_openapi(
  type: "Folder",
  action: :grant_access,
  title: "Folder - Grant Access",
  description: "Grant a role on this folder."
)
```

The generic copy stays on `ACTION_DEFINITIONS`. `openapi_for(:grant_access, type: "Folder")` applies the override. Accessible registers that lookup as `openapi_for:` on each capability action so Recording Studio API OpenAPI and the MCP catalog use the per-type copy.

Each action is `capability: :accessible`, `required_role: :admin`, member
scope. Handlers call `AccessManagementPolicy` and the Grant / Invite / Update /
Revoke services, so RoleCeiling, valid roles, shared-root refusal, and Access
child compatibility apply as they do in the UI. Inherited rows are read-only.
The error names the source recording to change instead. API invitation mail
uses the mailer's `default_url_options` because the handler has no controller
(`controller` is `nil`).

Current Recording Studio API does not auto-enable capability actions from the
`:accessible` mixin. List them on each type API:

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  operations: %i[index show create update destroy],
  capability_actions: %i[list_access grant_access update_access revoke_access],
  serializer: ->(workspace, **) { { name: workspace.name } },
  output_keys: %i[name]
)
```

A later RS_API release may enable these actions for types that already declare
`:accessible`. Until then, the type's `capability_actions` list is what makes
them callable and visible to MCP's generic `capability_action` tool.

Do not register `RecordingStudio::Access` as an API resource. Callers address
people through `actor_id` / `email` on the workspace, folder, press kit, or
other recording they already expose.

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

The same manage-access path can sit inside a Flatpack dropdown. The menu label is `Access` (no plus). A badge shows how many people have access. Flatpack menu items do not render avatars, so use the avatar helper when the faces should stay on the toolbar.

```erb
<%= render FlatPack::Button::Dropdown::Component.new(text: "More", style: :default, size: :sm) do |dropdown| %>
  <% recording_studio_accessible_access_menu_item(recording, dropdown, scope: :all) %>
<% end %>
```

`label:` replaces the item text for that call. `scope:` is `:direct` unless you pass `:all` or `:effective`. The item is omitted unless the current actor may manage access for that recording.

The missing-actor handler may return an actor, or a `RecordingStudioAccessible::MissingActorResolution`. An actor or `MissingActorResolution.created(...)` grants immediately. `:unresolved` asks the controller to call `invite_access`. `:invited` means the host already handled the invitation, and the addon stores nothing. `:invalid` and `:redirect` keep their previous behavior. Edit the copied templates under `app/views/recording_studio_accessible/access_granted_mailer/` when the grant mail is close. Replace `config.access_management_access_granted_notifier` when delivery has to change.

Default actor labels (manage-access rows, API `list_access` `actor.label`,
and `actor_label_for`) are the person's full name, then `name`, then email,
then `Type #id`. Full name is `first_name` and `last_name` joined, skipping
blanks. If the actor has neither, the same join runs on
`RecordingStudioUser.profile_for(actor)` when Recording Studio Users is
loaded. One present part is used on its own. Set
`config.access_management_actor_label` to replace that default. Use
`->(actor) { actor.email }` to keep email-first labels.

Manage-access row photos use `actor.avatar` or `actor.image` when that
value is a URL (or an object/`Hash` with `src` / `url` / `image_url`).
If Recording Studio Users is loaded, a profile image recording from
`profile_image_recording_for` is used next. Otherwise the row shows
FlatPack's user icon. Set `config.access_management_actor_avatar` to
replace that default. The callable should return a URL or nil.

By default, the mounted engine resolves the acting user from `Current.actor` so it follows the same actor source that RecordingStudio uses. It does not call `current_user` at all, public or private (Devise defines it public). Hosts must set `Current.actor` or override `config.access_management_current_actor_resolver`.

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

# Every actor with an effective role on this recording. Each entry is an
# ActorAccess: entry.actor, entry.role. role matches role_for for that actor.
# minimum_role defaults to :view (view < edit < admin).
RecordingStudioAccessible.actors_with_access(recording: page_recording, minimum_role: :edit)
```

`actors_with_access` walks the same path as `role_for`: the recording, its ancestors, and `root_recording_or_self`. It reads kept grants on that set in one query, drops a dependent grant that is not effective, and keeps the strongest role per actor. Actors are loaded per polymorphic type. A grant whose actor record is gone is skipped. Invitations and audience gates are not access grants, so they are not listed. There is no everyone row.

### Root ids for one actor

`authorized_root_recording_ids` returns the root recording ids `authorized?` would allow for that actor and role. The value is an `ActiveRecord::Relation` with one `id` column, so another query can filter with it:

```ruby
Notification.where(
  root_recording_id: RecordingStudioAccessible.authorized_root_recording_ids(actor: user)
)
```

`role` defaults to `:view`. `:edit` and `:admin` keep roots at that rank or higher. A nil actor, or a role other than `view`, `edit`, or `admin`, returns `RecordingStudio::Recording.none`.

A root is included only when a kept access grant for that actor sits on the root (`parent_recording_id` is the root). A grant that exists only on a child does not include the root. A dependent grant is included only when every manager hop is still a kept access recording on the same root, with a ranked role at least as strong, and the chain does not cycle. Trashed grants stay out. A trashed root stays in when `authorized?` still allows it.

Shared roots are included when that check passes. `root_recordings_for` and `root_recording_ids_for` still leave shared roots out of the actor-owned bucket list, and they still include a root reached only through a child grant. Audience rules and audience limits are not grants. They do not add or remove a root here, and they do not change `authorized?` on the root.

`authorized_root_recording_ids_supported?` is true for the default authorization service. A host that replaces the service and does not implement `authorized_root_recording_ids` gets false. Calling the query then raises `RecordingStudioAccessible::Error` and does not return a set. Use `authorized?` per recording in that case.

The manage-access page uses that lookup for each actor's effective role. A direct row is still shown when its own grant is not effective; the effective role on the row is the actor's real role, and it may be blank. The avatar rollup (`scope: :all` or `:effective`) loads kept grants for the recording and its ancestors in one query and preloads the actors. It still keeps the first grant it sees for an actor, including a dependent that is not effective. `LastAdminGuard` builds one lookup per recording after it takes the row locks. After the revoke or role change it reads grants again on that lookup, still inside the lock and with the query cache off. The answer from before the write is not reused.

### Recording ids under one root

`authorized_recording_ids` returns the recording ids under one root that `authorized?` would allow for that actor and role. The value is an unloaded `ActiveRecord::Relation` with one `id` column. Pass it to `where` so the filter stays in one query:

```ruby
RecordingStudio::Recording.where(
  id: RecordingStudioAccessible.authorized_recording_ids(actor: user, root: root_recording)
).limit(20)
```

`role` defaults to `:view`. `:edit` and `:admin` keep recordings at that rank or higher. A nil actor, a root that is not a recording, or a role other than `view`, `edit`, or `admin`, returns `RecordingStudio::Recording.none`.

The query is one recursive CTE over `parent_recording_id`. It does not load the children in Ruby and it does not paste an id list. A kept grant on a recording covers that recording and every descendant whose parent chain reaches the grant. A direct grant on a child does not cover the parent or a sibling. A stronger grant on an ancestor still covers the child. A grant on a recording's stored root counts for that recording even when the root sits off the parent chain. That grant does not cover a descendant that does not inherit it through the parent chain and does not store that same root.

Dependent grants count only when every manager hop is still a kept access recording on the same root, with a ranked role at least as strong, and the chain does not cycle. A trashed grant, a destroyed grant, and a voided dependent stay out. A kept grant on a trashed recording still counts. A trashed recording stays in the relation when `authorized?` allows it. Filter `trashed_at` on the caller's query when the list should be live rows only.

Audience rules and audience limits are not grants. They do not add or remove ids. Shared roots use the same check. A legacy grant on the shared root covers that root and the recordings under it. A grant that sits only on a child covers that child and its descendants, and leaves the shared root out.

`recordable_type` limits which ids come back. Inheritance still uses grants on other types. Pass a class or the stored type name, such as `"Page"`. A blank type returns `Recording.none`.

`authorized_recording_ids_supported?` is true for the default authorization service. A host that replaces the service and does not implement `authorized_recording_ids` gets false. Calling the query then raises `RecordingStudioAccessible::Error` and does not return a set. Use `authorized?` per recording in that case.

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

### Children under one parent

`recordings_for` returns the direct child recordings one actor can access under a parent. `recording_ids_for` returns the ids from that relation.

```ruby
RecordingStudioAccessible.recordings_for(
  actor: current_user,
  parent_recording: mount_recording,
  minimum_role: :view,
  recordable_type: "MessageGroup"
)
# => ActiveRecord::Relation of RecordingStudio::Recording

RecordingStudioAccessible.recording_ids_for(
  actor: current_user,
  parent_recording: mount_recording,
  minimum_role: :view,
  recordable_type: MessageGroup
)
# => Array of ids. Same membership as recordings_for(...).pluck(:id).
```

The same four keywords are on `RecordingStudioAccessible::Authorization`.

Candidates are direct children. `parent_recording_id` is the given parent. A grandchild stays out. The parent row stays out.

The actor is the exact actor. A host that also honors through-access keeps that check on `authorized_through?`.

A shared root is a valid parent. `recordings_for` lists authorized direct children under that parent, including a `MessageGroup` under `MessageRoot`. `root_recordings_for` lists actor-owned buckets and leaves shared roots out of that bucket list.

`Recording#recordings_for` wraps recordables in one root. It takes no actor.

`minimum_role` defaults to `nil`.

| `minimum_role` | Children that stay |
| --- | --- |
| `nil` or blank (`""`) | Any effective grant on the child or an ancestor, including an unranked name such as `download`. Same blank-floor rule as `root_recordings_for`. |
| `:view`, `:edit`, or `:admin` | That rank or higher. On a kept direct child this matches `authorized?`. |
| Present and unranked (`:download`, `"VIEW"`) | Empty relation. `recording_ids_for` returns `[]`. |

An unranked stored grant such as `download` qualifies when `minimum_role` is omitted. It does not satisfy a ranked floor.

`recordable_type` accepts a class or a non-blank string. The string is the `recordable_type` column. A class is stored as its name. Omit the argument and every authorized direct child stays, including `RecordingStudio::Access` rows on that parent. A symbol, an array, or `""` returns an empty relation.

Trashed children stay out. A trashed child can still pass `authorized?`. Trashed access grants do not count.

Audience rules and narrowing constraints are not grants. A public audience does not add a child. A narrower audience does not remove a child that `role_for` still allows.

The relation is the kept direct children, the optional type, and `id` in the ids that passed during the call. Chain `order`, `limit`, `includes`, and extra `where`. `unscope(:where)`, `rewhere(id:)`, and `or` drop that decision.

These calls return `RecordingStudio::Recording.none`, and `recording_ids_for` returns `[]`:

- `actor` is nil
- `parent_recording` is nil, is not a `RecordingStudio::Recording`, or has a blank id
- `minimum_role` is present and unranked (`:download`, `"VIEW"`)
- `recordable_type` is present and is not a class or a non-blank string

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
server-side. Built-in names (`public`, `signed_in`, `granted`) cannot be
redefined. Unknown audiences, missing policies, invalid config, and predicate
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

Checking several recordings under one root reads that root's rules and
constraints in one recordings query, then resolves each recording in memory.
`effective_audience` and `authorized_action?` are still one recording at a
time. A write in the same request clears the read, so the next check sees
the new rule. Allow and deny match a per-recording read, including a narrowed
audience, a dependent grant, and a trashed rule or recording.

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

Narrowing `config.action_audiences` in code is not persisted. Stored rules are
not rewritten, and there is no fallback event. Resolution still treats a
now-disallowed stored audience as `granted` until someone writes a new rule.

Accessible supplies the `define_action` policy for every action in
`action_audiences`. `authorized_action?` then checks the effective audience,
or the granted role when `granted_override` is on. If a host already defined
that action, Accessible logs a boot-time warning and the audience policy wins.
Actions that are not configured keep their existing host policies.

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

## Retitle manage access per recording

A host locale file under `recording_studio.accessible.*` changes every
manage-access screen. Use `config.access_management_copy` when one recording
should use different chrome, for example a workspace whose page says Teams.

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_management_copy = lambda do |recording:, **|
    recordable = recording&.recordable
    next unless recordable.is_a?(Workspace) && recordable.name == "Teams"

    { scope: "featured_in.teams" }
  end
end
```

Put the host strings under that scope, using the same relative keys as the gem:

```yaml
en:
  featured_in:
    teams:
      manage:
        title: "Teams"
        add: "+ Teammate"
        add_access: "+ Teammate"
        empty_title: "No teammates yet"
        empty_subtitle: "Invite someone onto this team."
        access_menu: "Teams"
      form:
        new_title: "Add a teammate"
        edit_title: "Change team access"
      requests:
        list_title: "Join requests"
```

Each chrome key looks up the host scope first, then
`recording_studio.accessible.*`. A missing host key falls back. The callable
may also return explicit strings (`{ "manage.title" => "Teams" }`) or both
(`{ scope: "featured_in.teams", copy: { "manage.add" => "+ Teammate" } }`).
This is the same `scope` / `copy` shape as access-request copy.

The engine resolves copy from the recording on the server. It does not read
titles from query params. If the callable raises or returns junk, the page
keeps the defaults.

The pack covers `manage.title`, `form.new_title`, `form.edit_title`,
`manage.add`, `manage.add_access`, `manage.empty_title`,
`manage.empty_subtitle`, `requests.list_title`, the default
`manage.access_menu` label on `recording_studio_accessible_access_menu_item`,
and the generated `recording_access_management_link` default. Flashes, errors,
mail, invitation accept, role names, and `recordables.access.label` stay on
the shared locale. Grants, roles, and authorization are unchanged.

The dummy app uses this on the workspace named Teams.

## Internationalization

The gem ships **English only** in `config/locales/en.yml`. Keys nest under `recording_studio.accessible.*`:

```ruby
t("recording_studio.accessible.manage.title")
t("recording_studio.accessible.actor_access_points.title", actor: label)
t("recording_studio.accessible.home.overview.title")
t("recording_studio.accessible.flashes.invitation_sent")
t("recording_studio.accessible.mailers.invitation.subject_with_recording", recording: name)
```

Customer invitation and manage-access screens, actor access points, engine demo/docs home pages, HomeController demo titles/status copy, validation and service error messages, and call-time recordable labels use these keys via `RecordingStudio.t` / `Copy.t` / `accessible_t`. When the active locale lacks a shipped key, fallback comes from the loaded English, host overrides included, then any caller `default:`, then the merged shipped-English table (Accessible registers its `en.yml` with `RecordingStudio::Translation.register_shipped_english` at boot). Ruby code samples on the demo Methods and User invites pages stay English. `recording_studio_recordable label:` strings are captured at class load and stay English. Hosts own other languages: define the same keys in the host `config/locales` (the engine does not re-append its locales). Do not add `RecordingStudio_Internationalization` as a dependency of this gem — it is optional on the host (the dummy uses it to switch English/French).

Config callables still win. If you set `access_invitation_subject`, `access_management_access_granted_subject`, `access_management_actor_label`, or a missing-actor error string, that copy is used instead of the locale default.

Role labels look up `recording_studio.accessible.roles.<name>` and fall back to the current humanize, so a custom host role still has a label.

Invitation and access-granted mail render inside `I18n.with_locale`. The default locale is the current one (the inviter's request when they send the mail). Set `config.access_notification_locale` to a locale or a callable when the host already knows the recipient's language. This gem does not add a locale column.

Stored names stay data: recording titles, people names, emails, and type names are not translated. Mailer bodies are whole-sentence keys with interpolation so translators see the full sentence.

Generator CLI text, developer-facing `ArgumentError`s, and controller-supplied demo examples on the home docs pages stay English.

Add [Recording Studio Internationalization](https://github.com/bowerbird-app/RecordingStudio_Internationalization) on the host when you want a language selector.

## Dummy app demo

The dummy app lives in `test/dummy/` and demonstrates Recording Studio Accessible on top of RecordingStudio. It pins the companion gems this addon is tested with: RecordingStudio `v6.14.0`, FlatPack `v0.1.356`, Trashable `v0.16.0`, Attachable `v0.23.0`, Users `v0.28.1`, Metrics `v0.8.0`, Cache `v0.6.3`, Admin `v2.13.0`, Root Switchable `v0.15.0`, Notifications `v0.15.0`, and (dummy only) Recording Studio Internationalization `v0.2.0`. Dummy development/test also pins Recording Studio API `v0.23.0`, Logs `v0.7.4`, Icons `v0.2.1`, and Moveable `v4.1.1` so access member actions run through the real dispatcher. Those companions declare `recording_studio >= 6.1.0` in their own gemspecs, so dummy Bundler does not need a Gem::Specification widen shim. Dummy layouts use FlatPack's rounded theme (`data-theme="rounded"`). The dummy Tailwind entry does not redeclare those color or radius tokens. Dummy offers English and French. The language selector sits in the top nav, to the left of the workspace switcher. French keys live in `test/dummy/config/locales/fr.yml`. The engine does not ship French.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

The dummy app configures actor types, through-authorization, avatars, and
`access_management_copy` in
`test/dummy/config/initializers/recording_studio_accessible.rb`. The workspace
named Teams retitles manage access. An unknown email stays an invitation until
the signup page creates the user and accepts.

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

`bundle exec rake test` is the gem suite. It does not boot the dummy Rails app, so it cannot see host models such as `RecordingStudio::Recording`, `User`, or FlatPack. Tests that need those real constants live under `test/dummy/test/` (including `test/dummy/test/unit/`) and run with `bin/rails test` from `test/dummy`.

If dummy app boot, assets, or migrations change, also run:

```bash
cd test/dummy
bin/rails db:migrate RAILS_ENV=test
bin/rails tailwindcss:build
```

## Documentation

The original template architecture docs remain in `docs/gem_template/` as reference material.
