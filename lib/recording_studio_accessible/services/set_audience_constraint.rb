# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class SetAudienceConstraint < BaseService
      FALLBACK_EVENT = "audience_fallback"

      def initialize(root:, action:, allowed_audiences:, actor:)
        @root = root
        @action = action
        @allowed_audiences = allowed_audiences
        @actor = actor
      end

      private

      def perform
        validate_request!

        recording = RecordingStudio::Recording.transaction do
          @root.lock!
          constraint_recording = upsert_constraint_recording!
          rewrite_disallowed_descendant_rules!
          constraint_recording
        end
        success(recording)
      rescue RecordingStudioAccessible::Error
        raise
      rescue ActiveRecord::RecordInvalid => e
        raise RecordingStudioAccessible::AudienceInvalid, e.message
      end

      def validate_request!
        raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_root_required") unless @root
        raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_action_invalid") unless valid_action?
        unless RecordingStudio.root_recording?(@root)
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_constraint_not_root")
        end
        if RecordingStudioAccessible::SharedRootAccess.target?(@root)
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.grant_denied")
        end
        unless AudienceResolver.configured?(@action) && AudienceResolver.valid_config?(@action)
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_action_not_configured")
        end
        unless authorized?
          raise RecordingStudioAccessible::AudienceUnauthorized, copy("errors.audience_constraint_unauthorized")
        end
        unless audience_parent_allowed?
          raise RecordingStudioAccessible::AudienceInvalid, copy("errors.audience_not_enabled")
        end

        extra = requested_audiences - host_allowed
        return if extra.empty?

        raise RecordingStudioAccessible::AudienceNotAllowed, copy("errors.audience_constraint_not_narrower")
      end

      def valid_action?
        @action.is_a?(Symbol) && !@action.to_s.strip.empty?
      end

      def authorized?
        return false unless @actor && @root

        RecordingStudioAccessible.authorized?(actor: @actor, recording: @root, role: :admin)
      end

      def audience_parent_allowed?
        RecordingStudioAccessible::Compatibility.audience_parent_allowed?(
          recording: @root,
          child_type: AudienceQuery::CONSTRAINT_TYPE
        )
      end

      def host_allowed
        @host_allowed ||= begin
          settings = AudienceResolver.resolved_settings(@action)
          Array(settings[:allowed]) | [AudienceRegistry::GRANTED]
        end
      end

      def requested_audiences
        @requested_audiences ||= begin
          names = Array(@allowed_audiences).filter_map do |name|
            normalized = name.is_a?(Symbol) ? name : name.to_s.strip.to_sym
            normalized if normalized.is_a?(Symbol) && !normalized.to_s.strip.empty?
          end
          names |= [AudienceRegistry::GRANTED]
          names.uniq
        end
      end

      def upsert_constraint_recording!
        existing = AudienceQuery.constraint_recording_for(root: @root, action: @action)
        if existing
          current = Array(existing.recordable.allowed_audiences).map(&:to_s).sort
          return existing if current == stored_audience_names.sort

          revise_constraint!(existing)
        else
          create_constraint!
        end
      end

      def create_constraint!
        RecordingStudioAccessible::AudienceWriteContext.allow do
          @root.record(
            RecordingStudio::AccessConstraint,
            actor: @actor,
            parent_recording: @root
          ) do |constraint|
            assign_constraint_attributes(constraint)
          end
        end
      end

      def revise_constraint!(constraint_recording)
        RecordingStudioAccessible::AudienceWriteContext.allow do
          RecordingStudio.root_recording_or_self(@root).revise(constraint_recording, actor: @actor) do |constraint|
            assign_constraint_attributes(constraint)
          end
        end
      end

      def assign_constraint_attributes(constraint)
        constraint.action = @action.to_s
        constraint.allowed_audiences = stored_audience_names
      end

      def stored_audience_names
        requested_audiences.map(&:to_s)
      end

      def rewrite_disallowed_descendant_rules!
        allowed = requested_audiences
        AudienceQuery.descendant_rule_recordings(root: @root, action: @action).find_each do |rule_recording|
          current = rule_recording.recordable.audience.to_s.strip.to_sym
          next if allowed.include?(current)

          previous_audience = current.to_s
          revised = rewrite_rule_to_granted!(rule_recording)
          log_fallback_event!(revised, previous_audience: previous_audience)
        end
      end

      def rewrite_rule_to_granted!(rule_recording)
        RecordingStudioAccessible::AudienceWriteContext.allow do
          RecordingStudio.root_recording_or_self(@root).revise(
            rule_recording,
            actor: @actor,
            metadata: { reason: FALLBACK_EVENT, action: @action.to_s }
          ) do |rule|
            rule.action = @action.to_s
            rule.audience = AudienceRegistry::GRANTED.to_s
          end
        end
      end

      def log_fallback_event!(rule_recording, previous_audience:)
        rule_recording.log_event!(
          action: FALLBACK_EVENT,
          actor: @actor,
          metadata: {
            action: @action.to_s,
            previous_audience: previous_audience,
            audience: AudienceRegistry::GRANTED.to_s
          },
          idempotency_key: fallback_idempotency_key(rule_recording, previous_audience: previous_audience)
        )
      end

      def fallback_idempotency_key(rule_recording, previous_audience:)
        "#{FALLBACK_EVENT}:#{rule_recording.id}:#{rule_recording.recordable_id}:#{previous_audience}"
      end

      def service_args
        {
          root_recording_id: @root&.id,
          action: @action,
          allowed_audiences: requested_audiences,
          actor_gid: global_id_string_for(@actor)
        }
      end
    end
  end
end
