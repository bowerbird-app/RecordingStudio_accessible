# Recording Studio Accessible

Recording Studio Accessible is the optional access-control addon for `RecordingStudio`.

It extracts the access-specific pieces that currently live in RecordingStudio core into a standalone engine so host apps can install access behavior intentionally instead of assuming it is always present.

## What the gem provides

- child-only `RecordingStudio::Access` recordables for direct grants under opted-in recordings
- `RecordingStudioAccessible.role_for`, `role_through`, `authorized?`, and `authorized_through?` for role lookup and authorization checks
- a mounted engine page for adding and removing direct access on a recording
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
gem "recording_studio", "~> 3.0"
gem "recording_studio_accessible"
```

Then run:

```bash
bundle install
bin/rails generate recording_studio:install
bin/rails generate recording_studio:migrations
bin/rails generate recording_studio_accessible:install
bin/rails generate recording_studio_accessible:access_management --link-helper
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

## Compatibility with RecordingStudio 3.0

Recording Studio Accessible targets RecordingStudio `3.0.0` and its
capability-owned child recordable contract. RecordingStudio core no longer ships
built-in access control, so this addon provides `RecordingStudio::Access`,
declares it as a child-only recordable, and registers it as metadata for the
`:accessible` capability.

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

RecordingStudio `3.0.0` requires each configured recordable to declare its
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

Useful RecordingStudio 3 introspection helpers:

```ruby
RecordingStudio.capability_child_recordables_for(:accessible)
# => ["RecordingStudio::Access"]

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

Host apps may optionally restrict which actor types can receive access grants:

```ruby
RecordingStudioAccessible.configure do |config|
  config.access_actor_types = ["User", "Workspace", "Company", "Team"]
end
```

When this list is blank or `nil`, existing behavior is preserved. When it is
set, `RecordingStudioAccessible.grant_access` rejects new grants for actor
types outside the configured list. Existing access records remain valid for
compatibility.

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
`RecordingStudioAccessible.grant_access` or
`RecordingStudioAccessible::Services::GrantRecordingAccess`.
When this addon is loaded, direct access grant creation raises a validation
error.

The supported grant path enforces placement, authorization, role validation, and
deduplication so each actor has at most one direct active access grant under a
given parent recording.

### Managing access through the mounted engine

If you mount `RecordingStudioAccessible::Engine`, the gem exposes a recording-scoped access management page at:

```text
/recording_studio_accessible/recordings/:recording_id/accesses
```

The page uses a blank layout, renders only FlatPack components, and lets authorized users add, update, and remove direct grants for the target recording.

The mounted addon overview, docs, and email-preview pages under `/recording_studio_accessible` are authorized separately from the recording-scoped access-management page. By default they are fail-closed unless the current actor has admin access to the resolved demo root recording. If your host app wants a different policy, override `config.mounted_page_authorizer`.

To set that up in a host app, run:

```bash
bin/rails generate recording_studio_accessible:access_management --link-helper
```

That generator:

- mounts `RecordingStudioAccessible::Engine` if it is not already mounted
- creates `config/initializers/recording_studio_accessible.rb` if it does not already exist
- copies overrideable share-email templates to `app/views/recording_studio_accessible/access_granted_mailer/`
- optionally creates a host helper with `recording_access_management_path` and `recording_access_management_link`

By default, the new-access form accepts an email address and resolves it against `User` records. If no existing user matches, Recording Studio Accessible keeps the current "not found" error until your host app decides whether to provision an account or redirect into a host-specific resolution flow. After a successful grant, the default notifier sends `RecordingStudioAccessible::AccessGrantedMailer` using the copied templates above. You can override the lookup step, missing-user behavior, share-email subject, destination URL, or the notifier itself:

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
  config.access_management_access_granted_subject = lambda do |recording:, **|
    "A recording was shared with you: #{RecordingStudio::Labels.title_for(recording.recordable)}"
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

The missing-actor handler may return an actor directly, or a `RecordingStudioAccessible::MissingActorResolution` describing whether the controller should grant access, render an error, or redirect into a host-app workflow. Prefer `:invalid` or `:requires_resolution` until your host app has actually verified the recipient and completed any required setup. Returning an actor or `MissingActorResolution.created(...)` continues the grant immediately. If the default mailer is close but not quite right, edit the copied templates under `app/views/recording_studio_accessible/access_granted_mailer/`. If you need a fully custom delivery strategy, replace `config.access_management_access_granted_notifier` entirely.

By default, the mounted engine resolves the acting user from `Current.actor` so it follows the same actor source that RecordingStudio uses. If your host app needs a different source, override `config.access_management_current_actor_resolver`. The built-in resolver only falls back to `controller.current_user` when `Current.actor` is unavailable.

The create flow works like this:

1. The controller submits the entered email to `config.access_management_actor_email_resolver`.
2. If that resolver returns an actor, the engine grants access to that actor immediately.
3. If no actor is found, the controller calls `config.access_management_missing_actor_handler`.
4. If that handler returns `MissingActorResolution.created(...)` or an actor, the engine grants access using that actor immediately.
5. If the grant succeeds, the controller calls `config.access_management_access_granted_notifier`.
6. The built-in notifier delivers `RecordingStudioAccessible::AccessGrantedMailer` with the configured subject and URL.

That separation is intentional:

- account lookup and optional account provisioning live in host-app configuration
- granting access lives in the engine service layer
- post-grant share notification lives in the notifier/mailer layer

### Checking access

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

## Dummy app demo

The dummy app lives in `test/dummy/` and demonstrates Recording Studio Accessible on top of the RecordingStudio dependency.

The dummy app also installs a demo-only override in `test/dummy/config/initializers/recording_studio_accessible.rb`. That initializer creates a `User` automatically when an unknown email is granted access, so the demo can show a successful end-to-end flow without requiring a separate invitation or signup system. That shortcut keeps the demo simple, but it is not the engine default and should not be treated as the recommended production pattern for host apps.

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

- `/` - dummy app demo with seeded folders, pages, cards, and access results
- `/recording_studio_accessible` - addon status/demo page
- `/recording_studio_accessible/recordings/:recording_id/accesses` - gem-provided page for managing direct recording access

The demo seeds:

- one workspace root recording
- folders and pages as recordable demo content
- cards attached to seeded pages
- multiple users with root, folder, page, and no-access states

That makes it obvious that the access feature is appearing because this addon is installed alongside RecordingStudio.

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
