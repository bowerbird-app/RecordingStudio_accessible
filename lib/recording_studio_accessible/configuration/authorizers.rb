# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Authorizers
      def authorize_access_management?(recording:, actor: nil, controller: nil)
        call_access_management_authorizer(recording: recording, actor: actor, controller: controller)
      end

      def authorize_mounted_page?(controller:, actor: nil, recording: nil)
        call_mounted_page_authorizer(controller: controller, actor: actor, recording: recording)
      end

      def authorize_actor_through?(**kwargs)
        callable = authorize_actor_through
        return false unless callable

        call_authorize_actor_through(callable, through_authorization_arguments(kwargs))
      end

      private

      def through_authorization_arguments(kwargs)
        extras = kwargs.except(:actor, :through, :recording, :role, :controller)
        extras.merge(
          actor: kwargs.fetch(:actor),
          through: kwargs.fetch(:through),
          recording: kwargs[:recording],
          role: kwargs[:role],
          controller: kwargs[:controller]
        )
      rescue KeyError => e
        raise ArgumentError, "missing keyword: #{e.key.inspect}"
      end

      def assign_authorizer_defaults
        @access_management_authorizer = method(:default_access_management_authorizer)
        @mounted_page_authorizer = method(:default_mounted_page_authorizer)
        @authorize_actor_through = method(:default_authorize_actor_through)
      end

      def default_access_management_authorizer(recording:, controller: nil, actor: nil)
        actor ||= current_actor_for(controller: controller)
        admin_authorized?(actor: actor, recording: recording)
      end

      def default_mounted_page_authorizer(controller:, actor: nil, recording: nil)
        actor ||= current_actor_for(controller: controller)
        admin_authorized?(actor: actor, recording: recording)
      end

      def default_authorize_actor_through(actor:, through:, recording: nil, role: nil, controller: nil)
        _recording = recording
        _role = role
        _controller = controller
        same_actor?(actor, through)
      end

      def admin_authorized?(actor:, recording:)
        return false unless actor && recording

        RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :admin)
      end

      def call_authorize_actor_through(callable, arguments)
        !!callable.call(**filtered_keyword_arguments(callable, arguments))
      rescue StandardError
        false
      end

      def call_access_management_authorizer(recording:, actor:, controller:)
        call_configured_authorizer(
          access_management_authorizer,
          recording: recording,
          actor: actor,
          controller: controller
        )
      end

      def call_mounted_page_authorizer(controller:, actor:, recording:)
        call_configured_authorizer(
          mounted_page_authorizer,
          controller: controller,
          actor: actor,
          recording: recording
        )
      end

      def call_configured_authorizer(callable, **kwargs)
        return false unless callable

        callable.call(**filtered_keyword_arguments(callable, kwargs))
      rescue StandardError
        false
      end

      def same_actor?(actor, through)
        return false unless actor && through
        return true if actor.equal?(through)
        return false unless comparable_actor_ids?(actor, through)

        RecordingStudioAccessible::ActorType.for(actor) == RecordingStudioAccessible::ActorType.for(through) &&
          actor.id == through.id
      end

      def comparable_actor_ids?(actor, through)
        actor.respond_to?(:id) && through.respond_to?(:id) && actor.id.present? && through.id.present?
      end
    end
  end
end
