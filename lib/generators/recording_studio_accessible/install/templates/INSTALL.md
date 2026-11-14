==============================================================================

Recording Studio Accessible has been installed successfully.

Next steps:
1. Review config/initializers/recording_studio_accessible.rb. Set `access_management_actor_scope` to the people this app may grant. An unset scope raises; it does not list every user.
2. Run `bin/rails generate recording_studio_accessible:migrations` if your RecordingStudio version no longer ships access migrations.
3. Run `bin/rails generate recording_studio_accessible:access_management --link-helper` if you want the mounted access-management UI. That generator mounts the engine if needed, preserves this initializer, and adds the optional host link helper.

==============================================================================
