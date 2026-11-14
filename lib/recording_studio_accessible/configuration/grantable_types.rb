# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module GrantableTypes
      def grantable_actor_types_for(controller: nil)
        types_from_grantable_scope(configured_actor_scope(controller))
      end

      private

      def types_from_grantable_scope(scope)
        klass = grantable_scope_klass(scope)
        return [normalize_access_actor_type(klass)].compact if klass
        return [normalize_access_actor_type(scope)].compact if scope.is_a?(Class)

        Array(scope).filter_map { |item| grantable_item_type(item) }.uniq
      end

      def grantable_scope_klass(scope)
        return unless scope.respond_to?(:klass)

        klass = scope.klass
        klass if klass.is_a?(Class)
      end

      def grantable_item_type(item)
        return normalize_access_actor_type(item) if item.is_a?(Class)
        return RecordingStudioAccessible::ActorType.for(item) if item.respond_to?(:id) && !item.is_a?(Symbol)

        nil
      end
    end
  end
end
