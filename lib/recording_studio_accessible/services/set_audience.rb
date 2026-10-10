# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class SetAudience < BaseService
      def initialize(recording:, action:, audience:, actor:)
        @recording = recording
        @action = action
        @audience = audience
        @actor = actor
      end

      private

      def perform
        validate_request!

        recording = RecordingStudio::Recording.transaction do
          lock_root_then_recording!
          ensure_audience_currently_allowed!
          upsert_rule_recording!
        end
        success(recording)
      rescue RecordingStudioAccessible::Error
        raise
      rescue ActiveRecord::RecordInvalid => e
        raise RecordingStudioAccessible::AudienceInvalid, e.message
      end

      def validate_request!
        raise RecordingStudioAccessible::AudienceInvalid, copy("errors.recording_required") unless @recording
        raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_action_invalid") unless valid_action?
        unless AudienceResolver.configured?(@action) && AudienceResolver.valid_config?(@action)
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_action_not_configured")
        end
        raise RecordingStudioAccessible::AudienceUnauthorized, copy("errors.audience_unauthorized") unless authorized?
        unless audience_parent_allowed?
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_not_enabled")
        end

        ensure_audience_currently_allowed!
      end

      def ensure_audience_currently_allowed!
        return if current_allowed_audiences.include?(normalized_audience)

        raise RecordingStudioAccessible::AudienceNotAllowed, copy("errors.audience_not_allowed")
      end

      def lock_root_then_recording!
        root = root_recording
        raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_root_required") unless root

        root.lock!
        return if @recording.id == root.id

        @recording.lock!
      end

      def valid_action?
        @action.is_a?(Symbol) && !@action.to_s.strip.empty?
      end

      def normalized_audience
        @normalized_audience ||= begin
          name = @audience.is_a?(Symbol) ? @audience : @audience.to_s.strip.to_sym
          name if name.is_a?(Symbol) && !name.to_s.strip.empty?
        end
      end

      def current_allowed_audiences
        AudienceResolver.allowed_audiences_for(recording: @recording, action: @action)
      end

      def audience_parent_allowed?
        RecordingStudioAccessible::Compatibility.audience_parent_allowed?(
          recording: @recording,
          child_type: AudienceQuery::RULE_TYPE
        )
      end

      def authorized?
        return false unless @actor && @recording

        manage_role = AudienceResolver.manage_role_for(@action)
        if RecordingStudio::AccessRoles.value_for(manage_role)
          RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: manage_role)
        else
          RecordingStudioAccessible.authorized_for_role?(actor: @actor, recording: @recording, role: manage_role)
        end
      end

      def upsert_rule_recording!
        existing = AudienceQuery.rule_recording_for(recording: @recording, action: @action)
        if existing
          return existing if existing.recordable.audience.to_s == normalized_audience.to_s

          revise_rule!(existing)
        else
          create_rule!
        end
      end

      def create_rule!
        RecordingStudioAccessible::AudienceWriteContext.allow do
          root_recording.record(
            RecordingStudio::AccessRule,
            actor: @actor,
            parent_recording: @recording
          ) do |rule|
            rule.action = @action.to_s
            rule.audience = normalized_audience.to_s
          end
        end
      end

      def revise_rule!(rule_recording)
        RecordingStudioAccessible::AudienceWriteContext.allow do
          root_recording.revise(rule_recording, actor: @actor) do |rule|
            rule.action = @action.to_s
            rule.audience = normalized_audience.to_s
          end
        end
      end

      def root_recording
        RecordingStudio.root_recording_or_self(@recording)
      end

      def service_args
        {
          recording_id: @recording&.id,
          action: @action,
          audience: normalized_audience,
          actor_gid: global_id_string_for(@actor)
        }
      end
    end
  end
end
