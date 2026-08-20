# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    def role_for(actor:, recording:)
      return nil unless actor

      call(actor: actor, recording: recording).value
    end

    def allowed?(actor:, recording:, role:)
      return false unless actor && recording && valid_role?(role)

      call(actor: actor, recording: recording, role: role).value
    end

    def allowed_through?(actor:, through:, recording:, role:, controller: nil)
      return false unless actor && through && recording && valid_role?(role)

      return false unless RecordingStudioAccessible.configuration.authorize_actor_through?(
        actor: actor,
        through: through,
        recording: recording,
        role: role,
        controller: controller
      )

      allowed?(actor: through, recording: recording, role: role)
    end

    def role_through(actor:, through:, recording:, controller: nil)
      return nil unless actor && through && recording

      return nil unless RecordingStudioAccessible.configuration.authorize_actor_through?(
        actor: actor,
        through: through,
        recording: recording,
        controller: controller
      )

      role_for(actor: through, recording: recording)
    end

    def root_recordings_for(actor:, minimum_role: nil)
      return [] unless actor

      root_recordings_relation_for(actor: actor, minimum_role: minimum_role).to_a
    end

    def root_recording_ids_for(actor:, minimum_role: nil)
      return [] unless actor

      root_recordings_relation_for(actor: actor, minimum_role: minimum_role).pluck(:id)
    end

    def access_recordings_for(recording)
      RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(recording)
    end

    def access_recordings_for_actor(recording:, actor:)
      RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: recording, actor: actor)
    end

    private

    def root_recordings_relation_for(actor:, minimum_role:)
      root_access_recordings = root_access_recordings_for(actor: actor, minimum_role: minimum_role)
      return RecordingStudio::Recording.none unless root_access_recordings.exists?

      relation = RecordingStudio::Recording.unscoped
                                           .where(id: root_access_recordings.select(:root_recording_id))
                                           .distinct
      exclude_shared_roots(relation)
    end

    def exclude_shared_roots(relation)
      return relation unless defined?(::RecordingStudio) && RecordingStudio.respond_to?(:shared_root_types)

      shared_root_types = RecordingStudio.shared_root_types
      return relation if shared_root_types.empty?

      relation.where.not(recordable_type: shared_root_types)
    end

    def root_access_recordings_for(actor:, minimum_role:)
      access_scope = access_scope_for(actor: actor, minimum_role: minimum_role)
      return RecordingStudio::Recording.none unless access_scope

      active_recordings_scope
        .where(recordable_type: "RecordingStudio::Access")
        .where.not(root_recording_id: nil)
        .where(recordable_id: access_scope.select(:id))
    end

    def access_scope_for(actor:, minimum_role:)
      scope = RecordingStudio::Access.where(
        actor_type: RecordingStudioAccessible::ActorType.for(actor),
        actor_id: actor.id
      )
      return scope if minimum_role.blank?

      minimum_value = RecordingStudio::Access.roles[minimum_role.to_s]
      return nil unless minimum_value

      scope.where(role: minimum_value..)
    end

    def active_recordings_scope
      scope = RecordingStudio::Recording.unscoped
      return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

      scope.where(trashed_at: nil)
    end

    def valid_role?(role)
      RecordingStudio::Access.roles.key?(role.to_s)
    end
  end
end
