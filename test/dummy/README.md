# Dummy App

This Rails app demonstrates **Recording Studio Accessible** as a separately installed addon on top of RecordingStudio.

## What it proves

- the host app installs `recording_studio_accessible` separately from `recording_studio`
- the addon mounts its own engine at `/recording_studio_accessible`
- seeded access data resolves through `RecordingStudio::Services::AccessCheck`
- the host app uses folders and pages as recordable demo content

## Quick Start

```bash
bundle install
bin/dev
```

`bin/dev` runs `bin/rails db:prepare` before starting Rails and Tailwind, so it will create or migrate the dummy database when needed.

Then sign in with:

- Email: `admin@admin.com`
- Password: `Password`

Additional seeded users:

- `editor@admin.com`
- `viewer@admin.com`
- `page_owner@admin.com`
- `outsider@admin.com`

All use `Password`.

## Useful Routes

- `/` - dummy app demo with seeded folders, pages, cards, and access results
- `/recording_studio_accessible` - addon status/demo page
- `/users/sign_in` - Devise sign-in page
