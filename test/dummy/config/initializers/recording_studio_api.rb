# frozen_string_literal: true

# Recording Studio API does not auto-enable capability actions from :accessible.
# List them on each type API. A later RS_API release may enable them for you.
return unless defined?(RecordingStudioApi)
return unless RecordingStudioApi.respond_to?(:register_recordable_type_api)

RecordingStudioApi.configure do |config|
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false if config.respond_to?(:rate_limit_fail_closed=)
  config.api_management_authorization_required = false
  config.documentation_enabled = false if config.respond_to?(:documentation_enabled=)
  # Dummy has no AdminRoot. Keep this empty so AdminApi's declaration does not
  # name an unregistered parent when CI eager-loads the model.
  config.admin_root_recordable_type_names = []
end

# AdminApi always declares recording_studio_recordable. The API engine only
# auto-registers it when a configured admin-root type constantizes.
if defined?(RecordingStudio)
  RecordingStudio.register_recordable_type("RecordingStudioApi::AdminApi")
end

ACCESS_MANAGEMENT_ACTIONS = %i[list_access grant_access update_access revoke_access].freeze

%w[Workspace Folder MessageGroup].each do |recordable_type|
  RecordingStudioApi.register_recordable_type_api(
    recordable_type,
    operations: %i[index show],
    capability_actions: ACCESS_MANAGEMENT_ACTIONS,
    serializer: lambda { |recordable, **|
      { name: recordable.try(:name) || recordable.try(:title) }
    },
    output_keys: %i[name]
  )
end
