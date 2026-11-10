# frozen_string_literal: true

require "recording_studio_accessible/api/actor_lookup"

module RecordingStudioAccessible
  module Api
    ACTOR_TYPE_NAME = /\A(?:[A-Z][A-Za-z0-9]*::)*[A-Z][A-Za-z0-9]*\z/

    class Error < StandardError; end

    class AuthorizationError < Error; end
    class NotFoundError < Error; end

    class InvalidInputError < Error
      attr_reader :details

      def initialize(message, details: [])
        super(message)
        @details = Array(details)
      end
    end

    module Payload
      module_function

      def actor(actor)
        return if actor.nil?

        {
          id: actor.id,
          type: ActorType.for(actor),
          label: RecordingStudioAccessible.configuration.actor_label_for(actor)
        }
      end

      def recording(recording)
        return if recording.nil?

        {
          id: recording.id,
          type: recording.recordable_type,
          label: recording_label(recording)
        }
      end

      def grant_row(row)
        {
          inherited: row.inherited,
          role: row.role&.to_s,
          effective_role: row.effective_role&.to_s,
          actor: actor(row.actor),
          source_recording: recording(row.source_recording)
        }
      end

      def recording_label(recording)
        recordable = recording.respond_to?(:recordable) ? recording.recordable : nil
        return Copy.t("errors.unknown") unless recordable
        return RecordingStudio::Labels.title_for(recordable) if defined?(RecordingStudio::Labels)

        return recordable.recordable_name if recordable.respond_to?(:recordable_name)
        return recordable.name if recordable.respond_to?(:name)
        return recordable.title if recordable.respond_to?(:title)

        recordable.class.name.demodulize
      end
    end

    class Handler
      include ActorLookup

      def self.call(context)
        handler = new(context)
        handler.ensure_access_children!
        handler.call
      end

      def initialize(context)
        @context = context
      end

      def ensure_access_children!
        return if Compatibility.access_management_allowed?(recording)

        raise not_found_error(Copy.t("errors.direct_access_not_enabled"))
      end

      private

      attr_reader :context

      def recording
        context.recording
      end

      def manager_actor
        grant = context.access_grant if context.respond_to?(:access_grant)
        return unless grant.respond_to?(:actor)

        grant.actor
      end

      def params
        raw = context.respond_to?(:params) ? context.params : nil
        return {} unless raw.respond_to?(:[])

        raw
      end

      def param(key)
        params[key].presence || params[key.to_s].presence
      end

      def authorize_management!
        return if AccessManagementPolicy.allowed?(recording: recording, actor: manager_actor)

        raise authorization_error(Copy.t("errors.not_authorized"))
      end

      def raise_service_failure!(result)
        message = result.error.to_s
        details = Array(result.errors).presence || [message]
        raise authorization_error(message) if message == Copy.t("errors.not_authorized")

        raise invalid_input_error(message, details: details)
      end

      def inherited_grant_error(row)
        source = Payload.recording(row.source_recording)
        message = Copy.t("errors.inherited_access", source_label: source.fetch(:label))
        invalid_input_error(message, details: [message])
      end

      def grant_list
        AccessGrantList.new(recording)
      end

      def direct_access_recording_for!(actor)
        row = grant_list.direct_row_for(actor)
        return row.access_recording if row

        inherited = grant_list.inherited_row_for(actor)
        raise inherited_grant_error(inherited) if inherited

        raise invalid_input_error(
          Copy.t("errors.access_recording_invalid"),
          details: [Copy.t("errors.access_recording_invalid")]
        )
      end

      def authorization_error(message)
        raise_named_error(:AuthorizationError, message, fallback: AuthorizationError)
      end

      def not_found_error(message)
        raise_named_error(:NotFoundError, message, fallback: NotFoundError)
      end

      def invalid_input_error(message, details: [])
        klass = api_error_class(:InvalidActionInputError) || InvalidInputError
        klass.new(message, details: details)
      end

      def raise_named_error(name, message, fallback:)
        klass = api_error_class(name) || fallback
        klass.new(message)
      end

      def api_error_class(name)
        return unless defined?(RecordingStudioApi)
        return unless RecordingStudioApi.const_defined?(name, false)

        RecordingStudioApi.const_get(name, false)
      end
    end
  end
end
