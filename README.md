# Recording Studio Accessible

Recording Studio Accessible is the optional access-control addon for `RecordingStudio`.

It extracts the access-specific pieces that currently live in RecordingStudio core into a standalone engine so host apps can install access behavior intentionally instead of assuming it is always present.

## What the gem provides

- `RecordingStudio::Access` recordables for root-level and recording-level grants
- `RecordingStudio::AccessBoundary` recordables for inheritance cutoffs
- `RecordingStudio::Services::AccessCheck` for role lookup and authorization checks
- install and migration generators for host apps
- a dummy Rails app that demonstrates the addon mounted separately from RecordingStudio

## Naming

This repository follows the template rename conventions for **Recording Studio Accessible**:

- Product name: `Recording Studio Accessible`
- Gem name: `recording_studio_accessible`
- Ruby namespace: `RecordingStudioAccessible`
- Engine namespace: `RecordingStudioAccessible::Engine`

The extracted public access API remains under `RecordingStudio::*` for compatibility with existing host code.

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
bin/rails generate recording_studio_accessible:migrations
bin/rails db:migrate
```

## Compatibility with current RecordingStudio releases

Current RecordingStudio releases may still ship the built-in access models and service.

When that happens, Recording Studio Accessible runs in **compatibility mode**:

- it does not redefine `RecordingStudio::Access`, `RecordingStudio::AccessBoundary`, or `RecordingStudio::Services::AccessCheck`
- it still registers the access recordable types with RecordingStudio
- it skips addon-owned access migrations because RecordingStudio core already owns those tables

When RecordingStudio core stops shipping those constants, this addon becomes the source of truth for the extracted access implementation.

## Setup notes

### RecordingStudio configuration

Your host app still configures RecordingStudio the normal way:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace"]
  config.actor = -> { Current.actor }
end
```

The addon automatically registers `RecordingStudio::Access` and `RecordingStudio::AccessBoundary` when it loads.

### Granting access

```ruby
access = RecordingStudio::Access.create!(actor: user, role: :view)

RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: access,
  parent_recording: root_recording
)
```

### Checking access

```ruby
RecordingStudio::Services::AccessCheck.role_for(actor: user, recording: root_recording)
RecordingStudio::Services::AccessCheck.allowed?(actor: user, recording: root_recording, role: :edit)
```

## Dummy app demo

The dummy app lives in `test/dummy/` and mounts both RecordingStudio and Recording Studio Accessible.

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
