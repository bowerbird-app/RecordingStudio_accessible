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
  # Dummy has no AdminRoot. API 1.2 only declares and registers AdminApi when
  # this list is non-empty, so leave it empty and do not register the type.
  config.admin_root_recordable_type_names = []
end

ACCESS_MANAGEMENT_ACTIONS = %i[list_access grant_access update_access revoke_access].freeze

%w[Workspace Folder MessageGroup PressKit].each do |recordable_type|
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

# Page is on the API and does not enable :accessible, so it gets no access tools.
RecordingStudioApi.register_recordable_type_api(
  "Page",
  operations: %i[index show],
  capability_actions: [],
  serializer: lambda { |recordable, **|
    { name: recordable.try(:title) }
  },
  output_keys: %i[name]
)

# Not an accessible recordable. The public name is Album, so an access tool
# would be grant_access_to_album rather than grant_access_to_kit.
module NamedMcpProbe
  class Kit
  end
end

RecordingStudioApi.register_recordable_type_api(
  "NamedMcpProbe::Kit",
  public_name: "Album",
  operations: %i[index show],
  capability_actions: [],
  auto_capability_actions: false,
  serializer: lambda { |recordable, **|
    { name: recordable.try(:name) }
  },
  output_keys: %i[name]
)
