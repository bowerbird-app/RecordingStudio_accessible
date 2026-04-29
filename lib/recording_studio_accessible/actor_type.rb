# frozen_string_literal: true

module RecordingStudioAccessible
  module ActorType
    class << self
      def for(actor)
        base_class = actor.class.base_class
        return base_class.polymorphic_name if base_class.respond_to?(:polymorphic_name)

        base_class.name
      end
    end
  end
end
