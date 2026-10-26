# frozen_string_literal: true

# Trashable v0.11.2 still includes this module. Recording Studio 6.1 removed
# it. Defining it here lets that engine load. Accessible controllers use
# recording_studio_layout and do not include this module.
module RecordingStudio
  module UsesDefaultLayout
    extend ActiveSupport::Concern

    included do
      recording_studio_layout { nil }
    end
  end
end
