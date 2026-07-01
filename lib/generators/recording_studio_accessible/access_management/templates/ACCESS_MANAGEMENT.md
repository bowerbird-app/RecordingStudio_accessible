==============================================================================

Recording Studio Accessible access management has been configured.

Next steps:
1. Review config/initializers/recording_studio_accessible.rb.
2. Link host pages to `/recording_studio_accessible/recordings/:recording_id/accesses` for the relevant `RecordingStudio::Recording`. The mounted UI supports adding, editing, and removing direct grants there.
3. If you generated the optional link helper, use `recording_access_management_link(recording)` from host views.
4. If you want to use the workspace actor access-point page, set `config.access_actor_types` to an explicit allowlist such as `["User", "Workspace"]`; that route fails closed when the allowlist is blank.

==============================================================================