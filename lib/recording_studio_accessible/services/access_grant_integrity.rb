# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class AccessGrantIntegrity < BaseService
      include AccessRecordLifecycle

      def initialize(dry_run: true, manager_actor: nil)
        @dry_run = dry_run
        @manager_actor = manager_actor
      end

      private

      attr_reader :dry_run, :manager_actor

      def perform
        return failure("A persisted manager actor with a GlobalID is required for repair") if !dry_run && !valid_manager_actor?

        ensure_current_impersonator_accessor! unless dry_run
        report = duplicate_groups.map { |group| inspect_or_repair(group) }
        failures = report.select { |entry| entry[:status] == :failed }

        return failure("Some duplicate access grants could not be repaired", errors: failures,
                                                                       value: { report: report, dry_run: dry_run }) if failures.any?

        success(report: report, dry_run: dry_run)
      end

      def service_args
        { dry_run: dry_run, manager_actor_gid: global_id_string_for(manager_actor) }
      end

      def valid_manager_actor?
        return false unless manager_actor.respond_to?(:id) && manager_actor.id.present?
        return false if manager_actor.respond_to?(:persisted?) && !manager_actor.persisted?

        manager_actor.respond_to?(:to_global_id)
      end

      def duplicate_groups
        active_access_recordings.includes(:recordable).to_a
                                .group_by { |recording| group_key_for(recording) }
                                .select { |_key, recordings| recordings.length > 1 }
                                .map do |key, recordings|
          group_from(key, recordings)
        end
      end

      def inspect_or_repair(group)
        return report_for(group, status: :skipped_no_valid_role) unless group[:strongest_role]
        return report_for(group, status: :would_repair) if dry_run

        repair(group)
      rescue StandardError => e
        report_for(group, status: :failed, error: e.message)
      end

      def repair(group)
        RecordingStudio::Recording.transaction do
          parent = RecordingStudio::Recording.unscoped.find(group[:parent_recording_id])
          parent.lock!
          current_group = group_for_parent(parent, group)
          return report_for(group, status: :resolved) unless current_group
          return report_for(current_group, status: :skipped_no_valid_role) unless current_group[:strongest_role]

          retained = current_group[:recordings].first
          if retained.recordable.role != current_group[:strongest_role] ||
             retained.recordable.actor_type != current_group[:actor_type]
            revise_access!(retained, role: current_group[:strongest_role], actor_type: current_group[:actor_type])
          end
          current_group[:recordings].drop(1).each do |access_recording|
            destroy_access_recording!(access_recording, manager_actor: manager_actor)
          end

          report_for(current_group, status: :repaired, retained: retained)
        end
      end

      def group_for_parent(parent, group)
        recordings = active_access_recordings_for(parent).includes(:recordable).select do |recording|
          group_key_for(recording) == [ parent.id, group[:actor_type], group[:actor_id] ]
        end
        return unless recordings.length > 1

        group_from(group_key_for(recordings.first), recordings)
      end

      def active_access_recordings
        scope = RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access")
        scope = scope.where(trashed_at: nil) if RecordingStudio::Recording.column_names.include?("trashed_at")
        scope.joins(DirectAccessQuery::ACCESS_JOIN_SQL).order(created_at: :desc, id: :desc)
      end

      def active_access_recordings_for(parent)
        active_access_recordings.where(parent_recording_id: parent.id)
      end

      def group_key_for(access_recording)
        access = access_recording.recordable
        [ access_recording.parent_recording_id, normalized_actor_type_for(access), access.actor_id ]
      end

      def normalized_actor_type_for(access)
        actor = access.actor
        return RecordingStudioAccessible::ActorType.for(actor) if actor

        access.actor_type
      end

      def group_from(key, recordings)
        roles = recordings.map { |recording| recording.recordable.role }
        strongest_role = roles.select { |role| RecordingStudio::AccessRoles.value_for(role) }
                            .max_by { |role| RecordingStudio::AccessRoles.value_for(role) }

        {
          parent_recording_id: key[0],
          actor_type: key[1],
          actor_id: key[2],
          recordings: recordings,
          access_recording_ids: recordings.map(&:id),
          roles: roles,
          strongest_role: strongest_role
        }
      end

      def report_for(group, status:, retained: nil, error: nil)
        retained ||= group[:recordings]&.first if group[:strongest_role]

        {
          parent_recording_id: group[:parent_recording_id],
          actor_type: group[:actor_type],
          actor_id: group[:actor_id],
          access_recording_ids: group[:access_recording_ids],
          roles: group[:roles],
          retained_access_recording_id: retained&.id,
          strongest_role: group[:strongest_role],
          status: status,
          error: error
        }
      end

      def revise_access!(access_recording, role:, actor_type:)
        RecordingStudioAccessible::AccessCreationContext.allow do
          RecordingStudio.root_recording_or_self(access_recording).revise(access_recording, actor: manager_actor) do |access|
            access.role = role
            access.actor_type = actor_type
          end
        end
      end
    end
  end
end