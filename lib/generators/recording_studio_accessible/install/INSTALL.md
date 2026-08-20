RecordingStudioAccessible install complete.

Next steps:

1. Review config/initializers/recording_studio_accessible.rb.
2. Enable `:accessible` on host recordables that should allow direct access grants. Do not enable it on shared root types; grant access on domain children beneath shared roots instead.
3. Run `bin/rails generate recording_studio_accessible:migrations` if your RecordingStudio version does not already provide access tables.
4. Mount `RecordingStudioAccessible::Engine` only if you want the optional addon status/demo page.
