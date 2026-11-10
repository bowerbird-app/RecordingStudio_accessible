# frozen_string_literal: true

# Recording Studio API does not auto-enable capability actions from :accessible.
# List them on each type API. A later RS_API release may enable them for you.
return unless defined?(RecordingStudioApi)
return unless RecordingStudioApi.respond_to?(:register_recordable_type_api)

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
