# frozen_string_literal: true

module RecordingStudioAccessible
  module ActorType
    class << self
      def for(actor)
        for_class(actor.class)
      end

      def for_class(klass)
        base_class = klass.respond_to?(:base_class) ? klass.base_class : klass
        return base_class.polymorphic_name if base_class.respond_to?(:polymorphic_name)

        base_class.name
      end
    end
  end
end
