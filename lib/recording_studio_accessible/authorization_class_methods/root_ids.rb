# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    # Roots authorized? would allow. Grants must sit on the root. Dependent
    # grants stay only when EffectiveRootIds says the manager chain is valid.
    # Shared roots and audience limits are not filtered out: authorized? does
    # not apply those rules.
    def authorized_root_recording_ids(actor:, role: :view)
      return RecordingStudio::Recording.none unless actor && valid_role?(role)

      grants = root_level_access_recordings_for(actor: actor, minimum_role: role)
      id_relation(effective_root_recording_ids(grants))
    end

    private

    def root_level_access_recordings_for(actor:, minimum_role:)
      recordings = RecordingStudio::Recording.arel_table
      root_access_recordings_for(actor: actor, minimum_role: minimum_role)
        .where(recordings[:parent_recording_id].eq(recordings[:root_recording_id]))
    end

    def id_relation(relation)
      connection = RecordingStudio::Recording.connection
      quoted = connection.quote_table_name(RecordingStudio::Recording.table_name)
      sql = connection.unprepared_statement { relation.to_sql }
      RecordingStudio::Recording.unscoped
                                .from(Arel.sql("(#{sql}) AS #{quoted}(id)"))
                                .reselect("#{quoted}.id")
                                .distinct
    end
  end
end
