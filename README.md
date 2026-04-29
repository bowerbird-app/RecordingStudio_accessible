# Recording Studio Accessible

Recording Studio Accessible is the optional access-control addon for `RecordingStudio`.

It extracts the access-specific pieces that currently live in RecordingStudio core into a standalone engine so host apps can install access behavior intentionally instead of assuming it is always present.

## What the gem provides

- `RecordingStudio::Access` recordables for root-level and recording-level grants
- `RecordingStudioAccessible.role_for` and `RecordingStudioAccessible.authorized?` for role lookup and authorization checks
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
gem "recording_studio"
gem "recording_studio_accessible"
```

Then run:

```bash
bundle install
bin/rails generate recording_studio_accessible:install
bin/rails generate recording_studio_accessible:access_management --link-helper
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

## Compatibility with current RecordingStudio releases

Current RecordingStudio releases may still ship the built-in access models.

When that happens, Recording Studio Accessible runs in **compatibility mode**:

- it does not redefine `RecordingStudio::Access`
- it still registers the access recordable types with RecordingStudio
- it skips addon-owned access migrations because RecordingStudio core already owns those tables

When RecordingStudio core stops shipping those constants, this addon becomes the source of truth for the extracted access implementation behind the `RecordingStudioAccessible` API.

## Setup notes

### RecordingStudio configuration

Your host app still configures RecordingStudio the normal way:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace"]
  config.actor = -> { Current.actor }
end
```

The addon automatically registers `RecordingStudio::Access` when it loads.

To allow direct access grants beneath a host recordable, opt that class in explicitly:

```ruby
class Workspace < ApplicationRecord
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_accessible_children :access
end
```

Without that opt-in, the mounted access-management UI and grant service reject direct access placements for the recordable.

### Granting access

```ruby
access = RecordingStudio::Access.create!(actor: user, role: :view)

RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: access,
  parent_recording: root_recording
)
```

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
