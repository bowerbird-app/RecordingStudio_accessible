# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Actors
      def grantable_actors_for(controller:)
        Array(resolve_configurable(access_management_actor_scope, controller))
      end

      def actor_label_for(actor)
        resolve_configurable(access_management_actor_label, actor)
      end

      def current_actor_for(controller: nil)
        resolve_configurable(access_management_current_actor_resolver, controller: controller)
      end

      def resolve_actor_for_email(controller:, email:)
        resolve_configurable(access_management_actor_email_resolver, controller: controller, email: email)
      end

      def access_actor_types=(types)
        @access_actor_types = if types == :all
                                :all
                              else
                                Array(types).filter_map { |type| normalize_access_actor_type(type) }.presence
                              end
      end

      def all_access_actor_types_allowed?
        access_actor_types == :all
      end

      def allowed_access_actor_type?(actor)
        return false unless valid_access_actor?(actor)
        return true if all_access_actor_types_allowed?
        return false if access_actor_types.blank?

        access_actor_types.include?(RecordingStudioAccessible::ActorType.for(actor))
      end

      private

      def assign_actor_defaults
        @access_management_actor_scope = method(:default_access_management_actor_scope)
        @access_management_current_actor_resolver = method(:default_access_management_current_actor_resolver)
        @access_management_actor_label = method(:default_access_management_actor_label)
        @access_management_actor_email_resolver = method(:default_access_management_actor_email_resolver)
        @access_actor_types = nil
      end

      def default_access_management_actor_scope(_controller)
        return [] unless defined?(::User)

        ordered_user_scope(::User.all)
      rescue StandardError
        []
      end

      def ordered_user_scope(scope)
        return scope.order(:email) if scope.respond_to?(:order) && ::User.column_names.include?("email")

        scope
      end

      def default_access_management_actor_label(actor)
        return Copy.t("errors.unknown_actor") unless actor

        actor_display_name(actor) || "#{actor.class.name.demodulize} ##{actor.id}"
      end

      def actor_display_name(actor)
        if actor.respond_to?(:email)
          actor.email.to_s.squish.presence
        elsif actor.respond_to?(:name)
          actor.name.to_s.squish.presence
        end
      end

      def default_access_management_current_actor_resolver(controller: nil)
        _controller = controller
        return unless defined?(Current) && Current.respond_to?(:actor)

        Current.actor.presence
      end

      def default_access_management_actor_email_resolver(controller:, email:)
        _controller = controller
        return unless user_email_lookup_available?

        find_user_by_email(email.to_s.strip.downcase)
      rescue StandardError
        nil
      end

      def user_email_lookup_available?
        defined?(::User) && ::User.respond_to?(:column_names) && ::User.column_names.include?("email")
      end

      def find_user_by_email(normalized_email)
        return if normalized_email.blank?

        if ::User.respond_to?(:where)
          ::User.where("LOWER(email) = ?", normalized_email).first
        elsif ::User.respond_to?(:find_by)
          ::User.find_by(email: normalized_email)
        end
      end

      def valid_access_actor?(actor)
        return false unless actor.respond_to?(:id) && actor.id.present?

        !actor.respond_to?(:persisted?) || actor.persisted?
      end

      def normalize_access_actor_type(type)
        normalized = type.is_a?(Class) ? class_access_actor_type(type) : type.to_s
        normalized.to_s.strip.presence
      end

      def class_access_actor_type(type)
        base_class = type.respond_to?(:base_class) ? type.base_class : type
        if base_class.respond_to?(:polymorphic_name)
          base_class.polymorphic_name
        else
          base_class.name
        end
      end
    end
  end
end
