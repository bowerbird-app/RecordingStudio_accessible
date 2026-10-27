# Recording Studio Accessible agent notes

Recording Studio Accessible is a Rails engine. Controllers, views, helpers, and mailers live in `app/`. The engine, configuration, and version live in `lib/recording_studio_accessible`. Generators live in `lib/generators`. Translations live in `config/locales`. Migrations live in `db/migrate`. Engine tests live in `test/` and do not boot the dummy Rails app. Tests that need real host models (`RecordingStudio::Recording`, `Access`, `User`, `Current`) or FlatPack live under `test/dummy/test/` (including `test/dummy/test/unit/`). `test/dummy` is the host app.

## Commands

One engine file:

```bash
bundle exec rake test TEST=test/configuration_test.rb
```

Engine suite (`rake test` in the Rakefile, CI job `test`):

```bash
bundle exec rake test
```

Dummy app suite, from `test/dummy` (same CI job):

```bash
bin/rails test
```

Lint: `bundle exec rubocop`.

Boot the dummy app from `test/dummy` with `bin/rails db:setup`, then `bin/rails tailwindcss:build`, then `bin/dev` (port 3000).

Version is `RecordingStudioAccessible::VERSION` in `lib/recording_studio_accessible/version.rb`.

## Working rules

Read files by line range. Search with a narrow path. Read only the top CHANGELOG entry, never the whole file. Pipe long command output through `tail`. Run the targeted test file before the full suite. Do not commit `docs/dummy-screenshots/` or a master key.
