# Dummy App

This Rails app demonstrates **Recording Studio Accessible** as a separately installed addon on top of RecordingStudio.

## What it proves

- the host app installs `recording_studio_accessible` separately from `recording_studio`
- the addon mounts its own engine at `/recording_studio_accessible`
- seeded access data resolves through `RecordingStudio::Services::AccessCheck`
- the host app continues to use normal RecordingStudio root-recording wiring

## Quick Start

```bash
bundle install
bin/dev
```

`bin/dev` runs `bin/rails db:prepare` before starting Rails and Tailwind, so it will create or migrate the dummy database when needed.

Then sign in with:

- Email: `admin@admin.com`
- Password: `Password`

A second seeded user is also available for the access demo:

- Email: `viewer@admin.com`
- Password: `Password`

## Useful Routes

- `/` - dummy app summary and seeded access results
- `/recording_studio` - RecordingStudio mount
- `/recording_studio_accessible` - addon status/demo page
- `/users/sign_in` - Devise sign-in page
- `/up` - Rails health check
