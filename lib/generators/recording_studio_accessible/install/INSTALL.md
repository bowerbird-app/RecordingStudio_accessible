RecordingStudioAccessible install complete.

Next steps:

1. Review config/initializers/recording_studio_accessible.rb.
2. Enable `:accessible` on host recordables that should allow direct access grants. Do not enable it on shared root types; grant access on domain children beneath shared roots instead.
3. Optional: set `config.action_audiences` for named actions, then enable `:action_audiences` on types that should hold audience rules or workspace limits. Constraints are valid only on a workspace. This gem does not ship a picker; host screens should use `audience_options_for` with Flatpack `RadioGroup`.
4. Run `bin/rails generate recording_studio_accessible:migrations` if your RecordingStudio version does not already provide access tables.
5. Mount `RecordingStudioAccessible::Engine` only if you want the optional addon status/demo page.
