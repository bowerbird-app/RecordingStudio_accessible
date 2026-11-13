# Changelog

All notable changes to this project will be documented in this file.

## [0.33.0] - 2026-11-13

### Added
- `RecordingStudioAccessible.actors_with_access(recording:, minimum_role: :view)`
  returns each actor with an effective role on that recording. The role is the
  strongest kept grant on the same path `role_for` uses. Actors load in batches
  per polymorphic type. Missing actors are skipped. Invitations and audience
  gates are not included.

### Changed
- `list_access` (`AccessGrantList.rows_for`) and `LastAdminGuard` use that
  batched lookup. Direct and inherited output, source, and pending invitations
  stay. A grant that is not effective (a dependent whose manager does not hold)
  is omitted. An inherited effective grant for that actor still shows.

### Upgrade notes
- No migration.
- `list_access` no longer returns an ineffective dependent grant. Filter
  nothing new to drop those rows; they are already gone. Call
  `actors_with_access` when you need the effective set rather than the grant
  list.

## [Unreleased]

### Changed
- Development pins move to Recording Studio `v6.7.0`, FlatPack `v0.1.356`,
  Trashable `v0.14.0`, Attachable `v0.23.0`, Users `v0.28.1`, Metrics `v0.8.0`,
  Cache `v0.6.3`, Admin `v2.13.0`, Logs `v0.7.4`, API `v0.23.0`, Moveable
  `v4.1.1`, and Icons `v0.2.1`. Dummy also pins Root Switchable `v0.15.0` and
  Notifications `v0.15.0`. Internationalization stays `v0.2.0`.
- Dummy recordings gain Trashable's nullable `purge_at` column. Dummy writes
  set `authorize_write` and `allow_unauthorized_writes` so seeds and tests can
  record before an actor is signed in.

### Upgrade notes
- No gemspec or version change. Re-bundle to pick up the release tags.
- Hosts on Recording Studio 6.5+ need `config.authorize_write`, or
  `config.allow_unauthorized_writes` when writes happen with no actor.
- Install Trashable `0.14.0`'s `purge_at` migration and restamp existing trash
  with `bin/rails recording_studio_trashable:restamp_purge_at`.

## [0.32.0] - 2026-11-13

### Added
- `RecordingStudioAccessible::Api.override_openapi` sets a per-type OpenAPI
  `title` and `description` for Accessible capability actions. Other types keep
  the generic `ACTION_DEFINITIONS` copy. Lookup is `openapi_for(action, type:)`.
  Registration now passes that lookup to Recording Studio API as `openapi_for:`,
  so OpenAPI and the MCP catalog use the per-type copy.
- `grant_access`, `list_access`, `revoke_access`, and `update_access` document
  real 200 schemas for the payloads those handlers already return.

### Changed
- `grant_access` with `actor_id` defaults `actor_type` to User when User is
  allowed, matching `update_access` and `revoke_access`. If User is not
  allowed, `actor_type` is still required.
- Generic OpenAPI descriptions and field wording for the four access actions
  now say that a second grant revises a direct grant, a known email is granted
  immediately, and inherited grants and invitations are not updated or
  revoked.
- Demoting the last admin uses
  "Add another admin before changing the last admin's role." Revoke still uses
  "Add another admin before removing the last one." `LastAdminGuard` is
  unchanged.

### Upgrade notes
- No migration.
- Clients may omit `actor_type` on `grant_access` when granting a User and
  User is in `access_actor_types`.
- Last-admin role-change errors now use `errors.last_admin_role_change`.
- Host gems can override title and description per recordable type without
  changing Accessible's generic copy. Recording Studio API 0.23.0 reads the
  registered `openapi_for:` callable.

## [0.31.0] - 2026-11-12

### Added
- `grant_access` and `update_access` API/MCP describe list default roles
  from `RoleSet::DEFAULT_NAMES` on the `role` field. Types may declare
  others. Validation stays on `role_valid_for?`.
- `list_access` includes unclosed email invitations from
  `AccessInvitation.pending_rows_for`. Those rows use `status: pending`
  (or `expired`), plus `email` and `role`. Direct and inherited grants
  use `status: granted`.

### Upgrade notes
- `list_access` `grants` is no longer grants-only. Pending invitation
  rows have no `actor`. Filter `status: granted` if you still want
  accepted grants alone.

## [0.30.0] - 2026-11-11

### Added
- `before_access_grant` runs before the new-access page
  (`source: :new_access`) and the invitation page
  (`source: :new_invitation`), after the existing access check. On new
  access, `role` and `actor` are nil and `granted_by` is the current
  actor. On the invitation page, `actor` is the signed-in invitee, `role`
  is the invitation role, and `granted_by` is the inviter.
  `GrantRefused` redirects or shows the alert the same way a refused write
  does. Any other error does not render the form. The write path is
  unchanged.

### Upgrade notes
- No migration. Leave `config.before_access_grant` unset and page
  behaviour stays the same.
- `:new_access` has a nil role and a nil grantee. `granted_by` is the
  current actor. `:new_invitation` uses the signed-in invitee, the
  invitation role, and the inviter, same as `:invite_acceptance`.

## [0.29.0] - 2026-11-11

### Added
- `config.before_access_grant` runs before a grant is created or its role
  changes. Default `nil` keeps current behaviour. The callable receives a
  frozen `GrantContext`. Raise `RecordingStudioAccessible::GrantRefused`
  (`message`, optional `redirect_to`) to refuse. Manage access redirects
  to that host path with `flash[:alert]`, or stays on the current page
  with the alert only. API `grant_access` / `update_access` return 422
  with the message (and `redirect_to` in the error details when set),
  not 500.
- The hook runs in `AccessGrantWriter#upsert_access_recording!` after the
  recording lock and built-in checks, so `grant_access`, `update_access`,
  invite acceptance, and access-request approval share one write path.
  Invite creation also runs it (`source: :invite`). Acceptance is the
  authoritative check.

### Upgrade notes
- Additive. Leave the config unset and nothing changes.
- Set `config.before_access_grant` for a host policy such as a seat cap.
  Count direct grants on the locked recording. This gem does not know
  about Stripe, plans, seats, or teams.
- `bootstrap_owner_access!` does not call the hook. A first owner is never
  blocked by default.
- `GrantRefused` is not wrapped in a service Result. Rescue it in a host
  controller if you call `grant_access` outside the mounted UI. Pass
  `redirect_to` when the host has a page that should show the flash.

## [0.28.0] - 2026-11-11

### Changed
- Default actor labels prefer a person's full name. `actor_label_for`
  (manage-access rows, API `list_access` `actor.label`, and other callers)
  joins `first_name` and `last_name` (blank parts skipped), then the same
  join on `RecordingStudioUser.profile_for(actor)`, then `name`, then
  `email`, then `Type #id`. One present part is used on its own. Host
  `config.access_management_actor_label` still wins.
- Manage-access list subtitles are the role only. Email is not repeated
  when the title is a name. Pending, expired, actor type, and inherited
  source stay on that line.
- Manage-access list items show a FlatPack avatar in the leading slot.
  The photo is duck-typed from `avatar` or `image` on the actor, then
  `RecordingStudioUser.profile_image_recording_for` when Users is loaded.
  Missing photos and pending invitations use FlatPack's user icon.
  `config.access_management_actor_avatar` replaces that default.

### Upgrade notes
- Behaviour change on the default label. People with a first or last name,
  or a Users profile, now show that name instead of email. Restore
  email-first labels with
  `config.access_management_actor_label = ->(actor) { actor.email }`,
  or keep a host callable that already sets the label.
- Hosts that copied the 0.27.1 list and joined `Role · email` when the
  title was a name should drop the email from the subtitle.
- Hosts that copied the manage-access list should pass `leading:` on
  each `FlatPack::List::Item` (photo or user icon). Restore a host photo
  with `config.access_management_actor_avatar`.

## [0.27.1] - 2026-11-11

### Changed
- Manage access lists people as `FlatPack::List` items (`layout: :items`,
  divider) instead of a `FlatPack::Table`. Each grant is one item: name as
  the title, role and email on a wrapping subtitle (pending invitations and
  inherited source stay on that line), and the existing actions dropdown as
  the trailing control. One markup at every width. Long emails wrap. When
  the title is already the email, the subtitle omits the email.
- `+ Access` and `Access requests` both sit in the outlined ButtonGroup
  overflow. A pending count is appended to the Access requests label so it
  still shows in the menu. The group still does not use `collapse: :menu`.

### Upgrade notes
- Hosts that copied the manage-access index should render
  `FlatPack::List::Component` / `FlatPack::List::Item` for people and
  inherited grants, not `FlatPack::Table`. Put `Access requests` in the
  ButtonGroup overflow (`overflow: true`) with `+ Access`. Do not set
  `collapse: :menu`.
- Grants, roles, policies, public helpers, and
  `config.access_management_copy` are unchanged.

## [0.27.0] - 2026-11-11

### Added
- `config.access_management_copy` retitles manage-access chrome for one
  recording. The callable receives `recording:` and `controller:` and returns
  nil, `{ scope: "featured_in.teams" }`, a hash of chrome keys, or both
  `scope` and `copy`. Lookup is host scope, then
  `recording_studio.accessible.*`. A missing host key, a raise, or junk
  keeps the defaults. Copy is resolved from the recording, never from a query
  param.

### Upgrade notes
- Additive. Default is nil, so existing screens keep current copy.
- Set `config.access_management_copy` when one recording needs different
  titles (for example Teams). A host locale file still changes every
  manage-access screen.
- Chrome only: titles, empty state, + button, requests title, access menu
  default, and the generated `recording_access_management_link` default.
  Flashes, errors, mail, invitation accept, role names, and
  `recordables.access.label` are unchanged.
- Regenerating `recording_studio_accessible:access_management --link-helper`
  switches the generated link default from hardcoded English to this lookup.

## [0.26.0] - 2026-11-11

### Changed
- `revoke_access`, `update_access` (when a role drops below admin), and
  `VoidDependentAccesses` refuse a write that would leave a recording with no
  effective admin. Effective admin is a kept, ranked `:admin` grant on the
  recording or an ancestor, the same resolution as `authorized?` /
  `AccessGrantList`. Pending invitations, trashed grants, and dependents whose
  manager is invalid do not count. The whole write rolls back. Destroying the
  recording itself is not guarded. `revoke_access_invitation` is not blocked.

### Added
- `RecordingStudioAccessible::LastAdminError` and copy key
  `recording_studio.accessible.errors.last_admin` ("Add another admin before
  removing the last one."). The manage-access UI flashes that text. Recording
  Studio API `update_access` and `revoke_access` return 422 with the same
  message.
- `allow_last_admin_removal: true` on `revoke_access` and `update_access`,
  passed through to the dependent-void cascade, for teardown and staff scripts.

### Upgrade notes
- Mild behaviour change. A host that relied on removing the last admin (for
  example emptying a workspace before delete) should pass
  `allow_last_admin_removal: true` or destroy the recording instead.
- Helper signatures stay compatible. The new keyword defaults to `false`.

## [0.25.0] - 2026-11-10

### Added
- Recording Studio API member actions `list_access`, `grant_access`,
  `update_access`, and `revoke_access` (`capability: :accessible`,
  `required_role: :admin`). They wrap the same policy and services as the
  manage-access UI. Inherited grants appear in `list_access` and cannot be
  updated or revoked. An email grant uses `invite_access`.
- `RecordingStudioAccessible.update_access` and `revoke_access` facades next
  to `grant_access`.

### Upgrade notes
- Additive. The gem does not depend on Recording Studio API. Actions register
  only when that gem is loaded. Current RS_API still needs each type API to
  list the actions in `capability_actions`. A later RS_API release may enable
  them for types that already declare `:accessible`.
- `RecordingStudio::Access` is not an API resource. List rows name the actor
  and the source recording only. `list_access` does not include pending
  invitations.
- `grant_access` with `actor_id` requires `actor_type` and only grants types
  the manage-access UI can grant. Email remains the people invite path.
- Shared roots 404 on every access action, matching the UI. `actor_type` is
  allowlisted before constantize. A host registration of the same action name
  with a different `required_role` is left in place and warned.

## [0.24.2] - 2026-11-05

### Changed
- Lockfiles move to Rails `8.1.4.1`, rack `3.2.8`, nokogiri `1.19.7`,
  loofah `2.25.3`, and rails-html-sanitizer `1.7.2`. Dummy also moves
  net-ssh to `7.3.8`. Bundler also pulled `io-console` `0.9.5`.

### Upgrade notes
- Run `bundle update rails rack nokogiri loofah rails-html-sanitizer`
  (and `net-ssh` if you lock it) so hosts pick up the same floors.

## [0.24.1] - 2026-11-04

### Changed
- Development pins move to Recording Studio `v6.3.0`, FlatPack `v0.1.341`,
  Users `v0.26.6`, Metrics `v0.7.2`, and Cache `v0.6.2`. Dummy also pins
  Root Switchable `v0.11.4`, Internationalization `v0.2.0`, and
  Notifications `v0.14.7`. Trashable is `v0.12.2`. Admin stays at
  `v2.5.1`. view_component stays at `4.19.0`.
- Cache, Users, Metrics, Internationalization, and Notifications now
  declare `recording_studio >= 6.1.0`, so Bundler no longer needs
  `test/support/widen_recording_studio_requirement.rb`.
- Lockfiles did not pick up extra RubyGems version changes besides those
  companion pins. Dummy Internationalization in the lockfile moves from
  `0.1.2` to `0.2.0` to match the `v0.2.0` tag. Cache in both lockfiles
  moves from `0.5.0` to `0.6.2`.
- Manage access keeps `Access requests` (and its pending count) in the
  outlined ButtonGroup row at every width. `+ Access` sits in that group's
  overflow menu. The group does not use `collapse: :menu`.

### Upgrade notes
- Point development and dummy Gemfiles at the tags above and run bundle
  update for those gems. The gemspec floor stays `recording_studio ~> 6.1,
  >= 6.1.0`.
- Hosts that copied the manage-access index should keep `Access requests`
  with `overflow: false` and put `+ Access` in the ButtonGroup overflow
  (`overflow: true`). Do not set `collapse: :menu`; that hides the pending
  count on phones.

## [0.24.0] - 2026-10-29

### Added
- `RecordingStudioAccessible.recordings_for` returns the direct child
  recordings one actor can access under a parent recording.
  `recording_ids_for` returns those ids. A ranked floor uses the same
  rule as `authorized?`. A blank floor keeps any effective grant.

### Upgrade notes
- Additive API. `authorized?`, grant writers, and `root_recordings_for`
  keep their current behavior.
- A blank `minimum_role` (`nil`, `""`) keeps a child that has any
  effective grant, including an unranked name such as `download`. That
  matches `root_recordings_for`. A ranked floor still uses
  `authorized?`. A present unranked floor (`:download`) stays empty.
- `recordings_for` returns an `ActiveRecord::Relation`.
  `root_recordings_for` returns an Array.
- The relation includes kept children only. A trashed child can still pass
  `authorized?` and stays out of this list.
- The actor is exact. Through-access stays on `authorized_through?`.

## [0.23.1] - 2026-10-28

### Changed
- Split `Configuration` into focused mixins so size cops apply without excludes.

## [0.23.0] - 2026-10-27

### Behaviour changes
- The default current-actor resolver reads `Current.actor`. It no longer
  falls back to `controller.current_user`, public or private, and no longer
  swallows errors. Hosts must set `Current.actor` or set
  `access_management_current_actor_resolver`.
- A present `config/recording_studio_accessible.yml` that cannot be parsed
  now fails at boot. A missing file still leaves configuration defaults.

### Changed
- Gem-suite tests no longer swap `RecordingStudio::Recording`, `Access`,
  `User`, `Current`, `ActiveRecord`, or `AccessGrantedMailer` with
  `const_set`. PORO cases that need those host constants now boot the dummy
  app under `test/dummy/test/unit/` and stub through Minitest or the public
  API. Helper tests use the real FlatPack components.

## [0.22.2] - 2026-10-27

### Changed
- Access request modals use FlatPack Modal. Open access-request dialogs
  still hide on `turbo:before-cache`, so Back/Forward does not restore a
  stale open modal. The request message uses Quote, modal headings use
  PageTitle (subtitle markup is `mt-2 text-lg`), and gate answers use
  List. Manage access actions use ButtonGroup. Table cells keep the
  table's own cell chrome instead of extra spans.
- `access_person_cell`, `access_actor_type_cell`, `access_role_cell`,
  `inherited_access_source_cell`, `inherited_access_source_role_cell`,
  `pending_invitation_role_cell`, and `inherited_access_actions_cell`
  return plain strings instead of styled spans. Person names no longer
  use `font-medium`.
- FlatPack stays at `0.1.319` or newer. ButtonGroup `variant: :outlined`
  first shipped in `0.1.307`.

### Removed
- Dummy `FlatPack::Tree` stand-in. The dummy tree page uses the real Tree
  component.

## [0.22.1] - 2026-10-27

### Changed
- Development pins move to FlatPack tag `v0.1.320`, Trashable `v0.12.0`,
  Attachable `v0.22.0`, Users `v0.25.2`, and Metrics `v0.6.1`. Dummy also
  pins Root Switchable `v0.11.0` and Notifications `v0.13.1`. Recording
  Studio stays at `v6.1.0`. Admin stays at `v2.5.1` because `v2.7.0`
  depends on `recording_studio_logs`.
- Cache, Users, Metrics, Internationalization, and Notifications still
  declare `recording_studio ~> 4.2`. Dummy Bundler still loads
  `test/support/widen_recording_studio_requirement.rb` so those gemspecs
  accept `6.1.0`.
- Install and access-management generators copy the access-granted mailer templates from one source.

### Removed
- Stop tracking SimpleCov `coverage/` output.
- Drop the dummy app's unused Rails-new GitHub workflow and Dependabot files.
- Remove leftover dummy scripts, the copied Flatpack page-nav controller, and the unused SVG icon sprite.
- Dummy FlatPack prepends for Root Switchable PageNav keywords and Card
  `style:`. Root Switchable `v0.11.0` no longer needs them.
- Dummy `UsesDefaultLayout` stub. Trashable `v0.12.0` no longer includes
  that removed Recording Studio module.

## [0.22.0] - 2026-10-26

### Changed
- Engine screens use Recording Studio's layout lookup. `config.layout` is
  `nil` until a host sets it. `nil` uses `RecordingStudio.configuration.layout`,
  then `recording_studio/default_layout`.
- Page titles come from `content_for :title` and `content_for :subtitle`.
  Back and close use `flat_pack_page_nav`. Manage access puts `+ Access`
  and `Access requests` in `recording_studio_page_nav_right`. The
  `+ Access` label is the button text, with no extra plus icon. Both
  actions use the default button style. Pending
  access requests on that recording add a count on `Access requests`.
  The direct-access table has no "People with access" section title.
  Access request filters are Flatpack pills. The active filter is the grey
  pill. A pending request badge uses the primary style. Approved and denied
  badges use the default style. On one request, the date is the page
  subtitle under the heading. The message stays in the page.
- Access-request modal frames still render with no document layout. On a
  full page, the same step shows one heading from the layout.
- Development pins move to `recording_studio` `v6.1.0` and `flat_pack`
  `0.1.319`. The gemspec floor is `~> 6.1`, `>= 6.1.0`.
- The access request list uses one Review button in the Actions column.
  The list has no note column. Review opens the request page in a modal,
  with the same heading, date, quoted message, gate answers, and Approve
  and Deny tabs. The Approve tab submits with Approve. The Deny tab submits
  with Deny. A save from that modal returns to the current filter. A save
  from the full request page stays on that page. The name still links to
  the request.

### Removed
- `recording_studio_accessible/blank` and
  `recording_studio_accessible/access_request` layouts.
- `accessible_document_attributes` and
  `recording_studio_accessible_flash_style`.

### Upgrade notes
- No migration. Install Accessible `0.22.0` with Recording Studio `>= 6.1.0`
  (this repo tests `v6.1.0`) and Flatpack `0.1.319`. Trashable stays
  `recording_studio_trashable ~> 0.10`. Do not add `recording_studio_user`
  to the Accessible gemspec.
- Leave `config.layout` unset to use the core layout, then the default
  shell. Set `RecordingStudio.configuration.layout` for every gem, or set
  `RecordingStudioAccessible.configuration.layout` for these screens only.
  A callable is `->(controller:) { "admin" }` and must return a layout name,
  `nil`, or `false`. A blank name or a positional parameter raises when you
  assign it. A bad return value raises when the screen renders.
- `false` skips the document layout and does not fall through to the core
  layout. Access-request Turbo frames still skip the layout, and they do
  not call a layout callable.
- A denied actor still fails closed before a layout callable runs.
- The date on a request page is the subtitle. A copied `access_requests/show`
  view that still prints the date in the body shows it twice until that
  copy moves the line into `content_for :subtitle` and the modal heading.
- Host `layout` `only` / `except` conditions no longer wrap these screens.
  The default shell does not set `html lang`. A host layout can.
- Delete host copies of the blank and access-request layouts. Replace an
  inline page title with `content_for`. Replace an inline page nav with
  `flat_pack_page_nav`. `FlatPack::Card` no longer accepts `style:`.
- Manage access no longer registers `+ Access` or `Access requests` with
  `register_page_nav`. Those actions render in
  `recording_studio_page_nav_right`. A host layout must render
  `:page_nav_right` or the buttons stay hidden. A copied
  `recording_accesses/index` view needs the same move.
- Sibling gems that still require `recording_studio` below 5 need a Bundler
  widen (see `test/support/widen_recording_studio_requirement.rb`) until
  those gems declare `>= 6.1.0`.
- Host copies of the access request list that still render an actions menu,
  or separate Approve and Deny buttons, need one Review button. The label is
  `requests.review`. Drop the note column from a copied list. Review loads
  the request page with `presentation=modal`. A copied `access_requests/show`
  view should quote the requester message and label the submit buttons
  Approve and Deny. A save from that modal returns to the list and keeps the
  filter. A save from the full request page stays on that page. A decision
  posted from the collection list returns to that list. A decision posted
  from any other list URL returns to that recording's request list, on the
  same filter.

## [0.21.0] - 2026-10-21

### Added
- `recording_studio_accessible_access_menu_item(recording, dropdown)` adds an
  Access row to a Flatpack `Button::Dropdown`. The label is
  `recording_studio.accessible.manage.access_menu` ("Access"). Pass `label:`
  to override it for one call. The row links to the same manage-access path
  as `recording_studio_accessible_avatars`. A badge shows how many people
  have access (`scope:` defaults to `:direct`, same as the avatar helper).

### Upgrade notes
- No migration. The avatar-group button is unchanged, including the `+ Access`
  label when nobody has an avatar yet.
- Hosts that copy `config/locales/en.yml` into another locale should add
  `manage.access_menu`. A missing translation still falls back to English
  through `Copy.t`.
- Flatpack dropdown items have a leading icon and a trailing badge. They do
  not have an avatar slot, so this row uses the badge for the count.

## [0.20.1] - 2026-10-20

### Added
- `config.layout`, a layout name or a callable (`controller:` keyword). When it
  is unset, each engine screen keeps the layout it uses today. Mounted docs
  stay on the host layout. Manage access, invitations, actor access points,
  and access-request pages stay on the engine layouts.

### Changed
- Development and dummy pins move to `recording_studio` `v4.7.1`, `flat_pack`
  `v0.1.275`, `recording_studio_trashable` `v0.11.2`, `recording_studio_admin`
  `v2.5.1`, and the other Recording Studio release tags named in the Gemfiles.
  The core gemspec floor is `~> 4.7, >= 4.7.1`. Trashable stays `~> 0.10`.
  `recording_studio_user` stays out of the gemspec.
- Engine page nav uses Flatpack's ordered rows (`with_close`). The close href
  is still a known route or the validated same-origin navigation helper.
- The manage-access primary button says `+ Access`. The new-access page is
  titled `Share access`, and its submit button says `Give access`. The role
  field is Flatpack's button radio group, with an icon on each role. The
  param stays `access[role]` and the role values are unchanged.
- Engine forms use Flatpack's medium width (`max-w-xl`, the same cap as a
  medium Flatpack modal). Phone screens stay full width of their container
  because that cap is wider than a phone.
- Share access, edit access, and access-request submit buttons have `pt-6`
  above them. Edit access is not wrapped in a card, so the form lines up with
  the title the same way Share access does. Width stays `max-w-xl`.

### Upgrade notes
- No migration.
- Hosts that override an engine page nav view need `with_back`, `with_link`,
  `with_close`, `with_action`, or `with_item`. Flatpack 0.1.274 removed the
  old PageNav keywords, and they now raise. This repo pins Flatpack `v0.1.275`.
- Leave `config.layout` unset to keep current layouts. Set a layout name, or a
  callable, when engine screens should use a host layout. The callable runs
  while the screen renders. It does not replace authentication or access
  checks. A denied actor stays denied when the callable raises. Access-request
  modal frames still render without a document layout.
- Hosts and tests that assert the old labels need the new copy. `Add access`
  is `+ Access`. `New access` is `Share access`. `Create access` is
  `Give access`.

## [0.20.0] - 2026-10-16

### Fixed
- An unregistered access-request action uses the `:default` gate on the form
  and again when the request is created.
- One pending request per person and target is enforced inside the row lock
  and by a partial unique index on the live pending row.
- Leaving approved revokes the grant even when that grant recording is trashed.
- A manager can grant a role they hold or a weaker ranked role. An admin can
  grant any role that recording accepts.
- Unexpected service errors are logged and shown as a generic message.
- A disabled email gets the same code page as any other email. Visitor
  codes go through `RecordingStudioUser.request_otp!`. A throttled result
  shows the rate-limit message. Issued and suppressed results show the same
  code page.

### Added
- `RecordingStudio::AccessRequest`, a child recordable of the target. Submit,
  re-submit, approve, deny, and reopen each revise the snapshot and append
  an event, so who did it and when stay on the history.
- `RecordingStudioAccessible.request_access`, `transition_access_request`,
  `approve_access_request`, and `deny_access_request`. One open request per
  person and target. A manager can move a request among pending, approved,
  and denied. Approval grants access in the same transaction. Leaving approved
  revokes that grant. Returning to pending clears the review stamps.
- Visitor screens for email, code, the request, and the confirmation. Each
  works as a full page and inside a Flatpack modal. The email step shows the
  recording's name or title, asks for a name, and passes that name to
  `complete_email_proof!` when the account is created. The request form does
  not ask for a role. The manager chooses the role when approving. Visitor
  copy can be overridden per flow with `copy:` or an I18n scope.
- Optional pre-request gate, `register_access_request_gate`, keyed by the
  requested action. An unregistered action uses the `:default` gate. The step sits after
  the email code and before the note. `create` checks it again. Continuation
  URLs must stay on the same host. A raising gate shows an alert and does not
  record the request. Sanitized answers are stored as `gate_metadata` on the
  snapshot at submit and re-submit, and managers see them beside the note.
  The name is required only when the user model requires one. A signed-in
  person skips the email code. Visitors get an account through Recording
  Studio Users (`request_otp!`, `verify_otp!`, `complete_email_proof!`). There
  is no guest path.
- `access_request_modal` for locked screens. Approval sends the existing
  access-granted email. Managers get `AccessRequestSubmittedMailer`. Hooks:
  `:access_request_submitted`, `:access_request_approved`, `:access_request_denied`,
  `:access_request_reopened`. Denial mail is sent only when
  `access_request_denied_notifier` is set.
- Manager index for one recording or many. `access_requests_index` embeds the
  same slice the engine routes render. The host passes the recordings.
  `AccessManagementPolicy` decides which rows are visible. Pending is the
  default status filter. The name column shows the requester, with the email
  underneath, or the email alone when there is no name. Notes stay on one line.
  Several recordings add a linked recording column. The row menu moves the
  request to another status.
  Further pages load with Flatpack infinite scroll.
- The request page names who asked and which recording, then the message and
  the date. Gate answers sit flush with that text. Approve and Deny are underline tabs.
  Approve picks a role with inline radios and icons. Save runs that status transition.
  The page, the email step, the code step, and the request form each work as
  a full page and inside the access request modal.

### Upgrade notes
- Run `rails generate recording_studio_accessible:migrations` and migrate.
  New tables: `recording_studio_access_requests` and
  `recording_studio_access_request_intents`. `gate_metadata` is added to
  `recording_studio_access_requests`.
- Accessible does not depend on Users in the gemspec. Users already depends
  on Accessible, and a gemspec dependency would cycle. Hosts that want the
  email-code screens add `recording_studio_user` 0.24.0 (with notifications
  and cache) the same way Messages does. Visitor codes call `request_otp!`.
  Point `Rails.cache` at a shared atomic store, and add a case-insensitive
  unique index on `users.email`. Without Users, `request_access` still works
  for an existing signed-in actor; the email step tells the visitor that
  codes are unavailable.
- The approve role picker uses Flatpack `RadioGroup` `variant: :inline`
  (Flatpack 0.1.212 or newer). The dummy pins Flatpack `v0.1.248`.

## [0.19.1] - 2026-10-16

### Changed
- Development and dummy Gemfiles pin `recording_studio_trashable` at `v0.11.0`.
  The gemspec constraint stays `~> 0.10`.

### Upgrade notes
- No migration. Hosts that resolve Trashable `~> 0.10` need no change.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.33.0...HEAD
[0.33.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.27.1...v0.28.0
[0.25.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.24.2...v0.25.0
[0.24.2]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.24.1...v0.24.2
[0.24.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.23.1...v0.24.0
[0.23.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.22.2...v0.23.0
[0.22.2]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.22.1...v0.22.2
[0.22.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.22.0...v0.22.1
[0.22.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.20.1...v0.21.0
[0.20.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.20.0...v0.20.1
[0.20.0]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.19.1...v0.20.0
[0.19.1]: https://github.com/bowerbird-app/RecordingStudio_accessible/compare/v0.19.0...v0.19.1
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
