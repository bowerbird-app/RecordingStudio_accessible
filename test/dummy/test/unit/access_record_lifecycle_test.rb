# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class AccessRecordLifecycleTest < Minitest::Test
      Recording = Struct.new(:id, :root_id, :parent_recording, :recordable_type, :recordable_id, :trashed_at,
                             keyword_init: true) do
        attr_reader :destroyed

        def parent_recording_id = parent_recording&.id
        def destroy! = @destroyed = true

        # Same predicate Trashable installs on Recording (kept? == !trashed_at.present?).
        def recording_studio_trashable_kept?
          trashed_at.nil?
        end
      end

      class Harness
        include AccessRecordLifecycle

        attr_reader :failure_message

        def failure(message) # rubocop:disable Naming/PredicateMethod
          @failure_message = message
          false
        end
      end

      def setup
        @harness = Harness.new
      end

      def test_authorize_access_management_returns_true_when_policy_allows
        RecordingStudioAccessible::AccessManagementPolicy.stub(:allowed?, true) do
          assert @harness.send(:authorize_access_management!, recording: :recording, manager_actor: :manager)
        end
      end

      def test_authorize_access_management_returns_failure_when_policy_denies
        RecordingStudioAccessible::AccessManagementPolicy.stub(:allowed?, false) do
          refute @harness.send(:authorize_access_management!, recording: :recording, manager_actor: :manager)
        end

        assert_equal "Not authorized to manage access", @harness.failure_message
      end

      def test_effective_manager_actor_falls_back_to_configuration_current_actor
        configuration = RecordingStudioAccessible.configuration

        configuration.stub(:current_actor_for, :current_actor) do
          assert_equal :current_actor, @harness.send(:effective_manager_actor, manager_actor: nil,
                                                                               controller: :controller)
        end
      end

      def test_valid_access_recording_for_parent_checks_parent_type_root_and_active_state
        parent = Recording.new(id: 1, root_id: 10)
        access_recording = Recording.new(id: 2, root_id: 10, parent_recording: parent,
                                         recordable_type: "RecordingStudio::Access", trashed_at: nil)

        RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
          assert @harness.send(:valid_access_recording_for_parent?, recording: parent,
                                                                    access_recording: access_recording)
        end

        trashed = Recording.new(id: 3, root_id: 10, parent_recording: parent,
                                recordable_type: "RecordingStudio::Access", trashed_at: Time.now)

        RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
          refute @harness.send(:valid_access_recording_for_parent?, recording: parent, access_recording: trashed)
          assert @harness.send(:revocable_access_recording?, recording: parent, access_recording: trashed)
        end
      end

      def test_destroy_access_recording_logs_event_destroys_recording_and_deletes_orphaned_access
        parent = Recording.new(id: 1, root_id: 10)
        access_recording = Recording.new(id: 2, root_id: 10, parent_recording: parent,
                                         recordable_type: "RecordingStudio::Access", recordable_id: 99)
        root = Object.new
        log_calls = []
        root.define_singleton_method(:log_event) do |recording, action:, actor:, metadata:|
          log_calls << [recording, action, actor, metadata]
        end

        deleted_ids = []
        access_relation = Object.new
        access_relation.define_singleton_method(:delete_all) { deleted_ids << 99 }
        recording_relation = Object.new
        recording_relation.define_singleton_method(:where) { |*| recording_relation }
        recording_relation.define_singleton_method(:none?) { true }

        RecordingStudio.stub(:root_recording_or_self, root) do
          RecordingStudio::Access.stub(:where, ->(id:) { access_relation }) do
            RecordingStudio::Recording.stub(:unscoped, recording_relation) do
              @harness.send(:destroy_access_recording!, access_recording, manager_actor: :manager)
            end
          end
        end

        assert access_recording.destroyed
        assert_equal [[parent, "deleted", :manager, { access_recording_id: 2, access_id: 99 }]], log_calls
        assert_equal [99], deleted_ids
      end

      def test_ensure_current_impersonator_accessor_is_idempotent_on_host_current
        @harness.send(:ensure_current_impersonator_accessor!)

        assert Current.method_defined?(:impersonator)
        assert Current.respond_to?(:impersonator)

        @harness.send(:ensure_current_impersonator_accessor!)

        assert Current.method_defined?(:impersonator)
      end
    end
  end
end
