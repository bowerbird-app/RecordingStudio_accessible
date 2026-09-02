# Dummy App

This Rails app demonstrates **Recording Studio Accessible** as a separately installed addon on top of RecordingStudio. It pins RecordingStudio `v4.2.0`, RecordingStudioRootSwitchable `v0.5.0`, and FlatPack `v0.1.133` so the demo matches the versions this addon is tested with. Layouts use FlatPack's rounded theme (`data-theme="rounded"`). RecordingStudio engine pages include `UsesDefaultLayout`.

## What it proves

- the host app installs `recording_studio_accessible` separately from `recording_studio`
- the addon mounts its own engine at `/recording_studio_accessible`
- seeded access data resolves through `RecordingStudioAccessible.role_for` and `RecordingStudioAccessible.authorized?`
- message groups demonstrate first-owner bootstrap on an accessible child under shared `MessageRoot`, then later members through `grant_access` (including `authorized_through?` with the demo workspace)
- the host app uses folders and pages as recordable demo content
- the demo initializer auto-creates missing users only to keep the walkthrough short; host apps should usually verify or route missing emails before granting access

## Quick Start

```bash
bundle install
bin/dev
```

`bin/dev` runs `bin/rails db:prepare` before starting Rails and Tailwind, so it will create or migrate the dummy database when needed.

The dummy Tailwind entry file scans FlatPack, RecordingStudio, and this addon's views/components. After changing companion gem pins, run `bin/rails tailwindcss:build` so utility classes from those gems are regenerated. The build first writes Bundler gem `@source` paths so FlatPack classes are included even when gems are installed outside `vendor/bundle`.

Then sign in with:

- Email: `admin@admin.com`
- Password: `Password`

Additional seeded users:

- `editor@admin.com`
- `viewer@admin.com`
- `page_owner@admin.com`
- `outsider@admin.com`

All use `Password`.

Cursor Cloud Agents start this dummy from the repo `.cursor/` hooks. Sign-in
is the same as above. See [Cursor skills in Cloud Agents](../../docs/cursor-skills.md).

## Seeded Workspaces

- `Accessible Demo Workspace` grants the admin root access, viewer access to all `access_user_*` accounts, and editor access to the Client onboarding folder.
- `Restricted Demo Workspace` grants only the admin root access and editor access to its Private planning folder. The viewer has no access, making it suitable for checking cross-workspace access controls.

## Seeded message groups

Shared-forest demo uses dummy class `MessageRoot` (`shared: true`). README examples may say `MessagesRoot` for the same pattern.

- `Client launch thread` sits under `Messages Root`.
- The first owner is `admin@admin.com`, granted with `bootstrap_owner_access!` on the group.
- Later access, including the through-workspace grant, uses `grant_access`.

Home and `/message_groups` both list groups the signed-in person can see.

## Useful Routes

- `/` - dummy app demo with seeded folders, pages, cards, message groups, and access results
- `/message_groups` - message groups under the shared messages root
- `/recording_studio_accessible` - addon status/demo page
- `/users/sign_in` - Devise sign-in page
