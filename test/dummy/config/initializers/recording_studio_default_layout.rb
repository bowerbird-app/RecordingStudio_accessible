# frozen_string_literal: true

# Ensure RecordingStudio engine pages use the shared default layout (back/close,
# rounded FlatPack theme). Host dummy screens keep the sidebar layout.
Rails.application.config.to_prepare do
  next unless defined?(RecordingStudio::ApplicationController)
  next unless defined?(RecordingStudio::UsesDefaultLayout)
  next if RecordingStudio::ApplicationController.included_modules.include?(RecordingStudio::UsesDefaultLayout)

  RecordingStudio::ApplicationController.include(RecordingStudio::UsesDefaultLayout)
end
