# Dummy App

This Rails app demonstrates **Recording Studio Accessible** as a separately installed addon on top of RecordingStudio. It pins RecordingStudio `v3.0.3`, RecordingStudioRootSwitchable `v0.3.5`, and FlatPack `v0.1.129` so the demo matches the versions this addon is tested with.

## What it proves

- the host app installs `recording_studio_accessible` separately from `recording_studio`
- the addon mounts its own engine at `/recording_studio_accessible`
- seeded access data resolves through `RecordingStudioAccessible.role_for` and `RecordingStudioAccessible.authorized?`
- message groups demonstrate `RecordingStudioAccessible.authorized_through?` with a separate `MessageRoot` root recordable
- the host app uses folders and pages as recordable demo content
- the demo initializer auto-creates missing users only to keep the walkthrough short; host apps should usually verify or route missing emails before granting access

## Quick Start

```bash
bundle install
bin/dev
```

`bin/dev` runs `bin/rails db:prepare` before starting Rails and Tailwind, so it will create or migrate the dummy database when needed.

The dummy Tailwind entry file scans FlatPack, RecordingStudio, and this addon's views/components. After changing companion gem pins, run `bin/rails tailwindcss:build` so utility classes from those gems are regenerated.

Then sign in with:

- Email: `admin@admin.com`
- Password: `Password`

Additional seeded users:

- `editor@admin.com`
- `viewer@admin.com`
- `page_owner@admin.com`
- `outsider@admin.com`

All use `Password`.

## Seeded Workspaces

- `Accessible Demo Workspace` grants the admin root access, viewer access to all `access_user_*` accounts, and editor access to the Client onboarding folder.
- `Restricted Demo Workspace` grants only the admin root access and editor access to its Private planning folder. The viewer has no access, making it suitable for checking cross-workspace access controls.

## Useful Routes

- `/` - dummy app demo with seeded folders, pages, cards, and access results
- `/message_groups` - message groups visible through the seeded workspace actor
- `/recording_studio_accessible` - addon status/demo page
- `/users/sign_in` - Devise sign-in page
