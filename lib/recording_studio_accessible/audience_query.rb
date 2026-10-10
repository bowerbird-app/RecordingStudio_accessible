# frozen_string_literal: true

module RecordingStudioAccessible
  module AudienceQuery
    CONSTRAINT_TYPE = "RecordingStudio::AccessConstraint"
    RULE_TYPE = "RecordingStudio::AccessRule"

    CONSTRAINT_JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_access_constraints
        ON recording_studio_access_constraints.id = recording_studio_recordings.recordable_id
    SQL

    RULE_JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_access_rules
        ON recording_studio_access_rules.id = recording_studio_recordings.recordable_id
    SQL

    class << self
      def constraint_recording_for(root:, action:)
        return if root.blank? || action.blank?
        return unless tables_available?

        live_recordings
          .where(parent_recording_id: root.id, recordable_type: CONSTRAINT_TYPE)
          .joins(CONSTRAINT_JOIN_SQL)
          .where(recording_studio_access_constraints: { action: action.to_s })
          .order(created_at: :desc, id: :desc)
          .first
      end

      def rule_recording_for(recording:, action:)
        return if recording.blank? || action.blank?
        return unless tables_available?

        live_recordings
          .where(parent_recording_id: recording.id, recordable_type: RULE_TYPE)
          .joins(RULE_JOIN_SQL)
          .where(recording_studio_access_rules: { action: action.to_s })
          .order(created_at: :desc, id: :desc)
          .first
      end

      def descendant_rule_recordings(root:, action:)
        return RecordingStudio::Recording.none if root.blank? || action.blank?
        return RecordingStudio::Recording.none unless tables_available?

        root_id = RecordingStudio.root_recording_id_for(root)
        return RecordingStudio::Recording.none if root_id.blank?

        live_recordings
          .where(root_recording_id: root_id, recordable_type: RULE_TYPE)
          .joins(RULE_JOIN_SQL)
          .where(recording_studio_access_rules: { action: action.to_s })
          .order(created_at: :asc, id: :asc)
      end

      def live_duplicate_exists?(recordable_type:, parent_recording_id:, action:, except_id: nil)
        return false if parent_recording_id.blank? || action.blank?
        return false unless tables_available?

        table_name, join_sql = join_for(recordable_type)
        return false unless table_name

        scope = live_recordings
                .where(parent_recording_id: parent_recording_id, recordable_type: recordable_type)
                .joins(join_sql)
                .where(table_name => { action: action.to_s })
        scope = scope.where.not(id: except_id) if except_id.present?
        scope.exists?
      end

      private

      def live_recordings
        scope = RecordingStudio::Recording.unscoped
        return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

        scope.where(trashed_at: nil)
      end

      def join_for(recordable_type)
        case recordable_type
        when CONSTRAINT_TYPE
          [:recording_studio_access_constraints, CONSTRAINT_JOIN_SQL]
        when RULE_TYPE
          [:recording_studio_access_rules, RULE_JOIN_SQL]
        end
      end

      def tables_available?
        return false unless defined?(::RecordingStudio::Recording)
        return false unless defined?(::RecordingStudio::AccessConstraint)
        return false unless defined?(::RecordingStudio::AccessRule)

        connection = ActiveRecord::Base.connection
        connection.data_source_exists?("recording_studio_access_constraints") &&
          connection.data_source_exists?("recording_studio_access_rules")
      rescue StandardError
        false
      end
    end
  end
end
