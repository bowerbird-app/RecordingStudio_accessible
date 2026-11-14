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

      def rows_for(recordings)
        return [] unless tables_available?

        parent_ids = parent_ids_for(recordings)
        return [] if parent_ids.empty?

        kept_audience_rows.where(parent_recording_id: parent_ids).to_a
      rescue StandardError
        []
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

      def kept_audience_rows
        live_recordings.where(recordable_type: [RULE_TYPE, CONSTRAINT_TYPE])
                       .preload(:recordable).order(created_at: :desc, id: :desc)
      end

      def parent_ids_for(recordings)
        ids = []
        Array(recordings).compact.each do |recording|
          ids << recording.id if recording.respond_to?(:id) && recording.id.present?
          root = RecordingStudio.root_recording_or_self(recording)
          ids << root.id if root.respond_to?(:id) && root.id.present?
        end
        ids.uniq
      end

      def live_recordings
        scope = RecordingStudio::Recording.unscoped
        return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

        # Additive kept filter (same as main). See DirectAccessQuery#active_recordings_scope.
        scope.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
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

  # Kept rules and constraints for every parent in one root. One recordings query.
  class AudienceRootRows
    def self.for(root)
      return [] unless root.respond_to?(:id) && root.id.present?
      return [] unless AudienceQuery.send(:tables_available?)

      parents = RecordingStudio::Recording.unscoped
      parent_ids = parents.where(root_recording_id: root.id).or(parents.where(id: root.id)).select(:id)
      AudienceQuery.send(:kept_audience_rows).where(parent_recording_id: parent_ids).to_a
    rescue StandardError
      []
    end
  end
  private_constant :AudienceRootRows

  # Newest kept rule or constraint per parent, type, and action.
  class AudienceSnapshot
    def self.load(recordings)
      new(AudienceQuery.rows_for(recordings))
    end

    def self.load_for_root(root)
      new(AudienceRootRows.for(root))
    end

    def initialize(rows)
      @by_key = {}
      Array(rows).each do |row|
        recordable = row.recordable
        next unless recordable

        key = [row.parent_recording_id, row.recordable_type, recordable.action.to_s]
        @by_key[key] ||= row
      end
    end

    def rule_for(recording:, action:)
      row_for(recording&.id, AudienceQuery::RULE_TYPE, action)
    end

    def constraint_for(root:, action:)
      row_for(root&.id, AudienceQuery::CONSTRAINT_TYPE, action)
    end

    private

    def row_for(parent_id, recordable_type, action)
      return if parent_id.blank? || action.blank?

      @by_key[[parent_id, recordable_type, action.to_s]]
    end
  end
end
