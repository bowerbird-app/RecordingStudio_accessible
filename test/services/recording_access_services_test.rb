# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class RecordingAccessServicesTest < Minitest::Test
      Recording = Struct.new(:id, :parent_recording_id, :recordable_type, :root_id, keyword_init: true) do
        attr_reader :locked

        def lock! = @locked = true
      end
      Actor = Struct.new(:id) do
        def self.base_class = self
      end

      def setup
        ensure_recording_class!
        ensure_access_class!
        ensure_active_record_error_class!
        @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
        RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
        RecordingStudioAccessible.configuration.access_management_current_actor_resolver = ->(controller:) { controller }
        RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
        RecordingStudioAccessible.configuration.access_actor_types = [Actor]
      end

      def teardown
        RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
        RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
        RecordingStudio.send(:remove_const, :Access) if @created_access_class
        Object.send(:remove_const, :ActiveRecord) if @created_active_record_module
      end

      def test_grant_access_validates_required_inputs
        actor = Actor.new(1)

        assert_equal "Recording is required",
                     GrantRecordingAccess.call(recording: nil, actor: actor, role: :view).error
        assert_equal "Actor is required",
                     GrantRecordingAccess.call(recording: Recording.new(id: 1), actor: nil, role: :view).error
      end

      def test_grant_access_validates_authorization_access_type_and_role
        recording = Recording.new(id: 1)
        actor = Actor.new(1)

        RecordingStudioAccessible::AccessManagementPolicy.stub(:allowed?, false) do
          assert_equal "Not authorized to manage access",
                       GrantRecordingAccess.call(recording: recording, actor: actor, role: :view).error
        end

        RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, false) do
          assert_equal "Direct access is not enabled for this recording",
                       GrantRecordingAccess.call(recording: recording, actor: actor, role: :view).error
        end

        RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, true) do
          RecordingStudioAccessible.configuration.access_actor_types = [String]
          assert_equal "Actor type is not allowed for access",
                       GrantRecordingAccess.call(recording: recording, actor: actor, role: :view).error
          RecordingStudioAccessible.configuration.access_actor_types = [Actor]

          assert_equal "Role is invalid",
                       GrantRecordingAccess.call(recording: recording, actor: actor, role: :owner).error
        end
      end

      def test_grant_access_creates_new_access_recording
        recording = Recording.new(id: 1)
        actor = Actor.new(1)
        root = RootRecorder.new(:created_recording)
        service = GrantRecordingAccess.new(recording: recording, actor: actor, role: :edit, manager_actor: :manager)

        RecordingStudio.stub(:root_recording_or_self, root) do
          assert_equal :created_recording, service.send(:create_access_recording)
        end

        assert_equal [[RecordingStudio::Access, :manager, recording, actor, "edit"]], root.record_calls
      end

      def test_grant_access_updates_existing_access_recording_and_deduplicates_extras
        recording = Recording.new(id: 1)
        actor = Actor.new(1)
        existing = Recording.new(id: 2, parent_recording_id: 1, recordable_type: "RecordingStudio::Access")
        duplicate = Recording.new(id: 3, parent_recording_id: 1, recordable_type: "RecordingStudio::Access")
        root = RootRecorder.new(:revised_recording)
        service = GrantRecordingAccess.new(recording: recording, actor: actor, role: :admin, manager_actor: :manager)

        service.stub(:destroy_access_recording!, ->(access_recording, manager_actor:) { access_recording.root_id = manager_actor }) do
          RecordingStudio.stub(:root_recording_or_self, root) do
            assert_equal :revised_recording,
                         service.send(:update_existing_access_recording, existing, [existing, duplicate])
          end
        end

        assert_equal :manager, duplicate.root_id
        assert_equal [[existing, :manager, "admin"]], root.revise_calls
      end

      def test_grant_perform_returns_success_for_valid_request
        service = GrantRecordingAccess.new(recording: Recording.new(id: 1), actor: Actor.new(1), role: :view,
                                           manager_actor: :manager)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:upsert_access_recording!, :access_recording) do
              result = service.send(:perform)

              assert result.success?
              assert_equal :access_recording, result.value
            end
          end
        end
      end

      def test_grant_perform_returns_failure_for_unexpected_errors
        service = GrantRecordingAccess.new(recording: Recording.new(id: 1), actor: Actor.new(1), role: :view,
                                           manager_actor: :manager)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:upsert_access_recording!, -> { raise "boom" }) do
              result = service.send(:perform)

              assert result.failure?
              assert_equal "boom", result.error
            end
          end
        end
      end

      def test_grant_upsert_creates_or_updates_inside_transaction
        recording = Recording.new(id: 1)
        actor = Actor.new(1)
        service = GrantRecordingAccess.new(recording: recording, actor: actor, role: :view, manager_actor: :manager)

        service.stub(:existing_access_recordings, []) do
          service.stub(:create_access_recording, :created) do
            assert_equal :created, service.send(:upsert_access_recording!)
          end
        end

        existing = Recording.new(id: 2)
        service.stub(:existing_access_recordings, [existing]) do
          service.stub(:update_existing_access_recording, :updated) do
            assert_equal :updated, service.send(:upsert_access_recording!)
          end
        end

        assert recording.locked
      end

      def test_update_access_validates_inputs
        recording = Recording.new(id: 1)

        assert_equal "Recording is required",
                     UpdateRecordingAccess.call(recording: nil, access_recording: Recording.new(id: 2), role: :view).error
        assert_equal "Access recording is required",
                     UpdateRecordingAccess.call(recording: recording, access_recording: nil, role: :view).error
      end

      def test_update_access_validates_access_recording_and_role
        recording = Recording.new(id: 1)
        access_recording = Recording.new(id: 2, parent_recording_id: 999, recordable_type: "RecordingStudio::Access")

        RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, true) do
          assert_equal "Access recording is invalid",
                       UpdateRecordingAccess.call(recording: recording, access_recording: access_recording, role: :view,
                                                  manager_actor: :manager).error
          service = UpdateRecordingAccess.new(recording: recording, access_recording: valid_access_recording(recording),
                                              role: :owner, manager_actor: :manager)
          service.stub(:valid_access_recording_for_parent?, true) do
            assert_equal "Role is invalid", service.send(:perform).error
          end
        end
      end

      def test_update_access_revises_valid_access_recording
        recording = Recording.new(id: 1)
        access_recording = valid_access_recording(recording)
        root = RootRecorder.new(:updated_recording)
        service = UpdateRecordingAccess.new(recording: recording, access_recording: access_recording, role: :admin,
                                            manager_actor: :manager)

        RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, true) do
          service.stub(:valid_access_recording_for_parent?, true) do
            RecordingStudio.stub(:root_recording_or_self, root) do
              result = service.send(:perform)

              assert result.success?
              assert_equal :updated_recording, result.value
            end
          end
        end
      end

      def test_revoke_access_validates_inputs_and_invalid_recording
        recording = Recording.new(id: 1)

        assert_equal "Recording is required",
                     RevokeRecordingAccess.call(recording: nil, access_recording: Recording.new(id: 2)).error
        assert_equal "Access recording is required",
                     RevokeRecordingAccess.call(recording: recording, access_recording: nil).error
        assert_equal "Access recording is invalid",
                     RevokeRecordingAccess.call(recording: recording,
                                                access_recording: Recording.new(id: 2, parent_recording_id: 999,
                                                                                recordable_type: "RecordingStudio::Access"),
                                                manager_actor: :manager).error
      end

      def test_revoke_access_destroys_valid_access_recording
        recording = Recording.new(id: 1)
        access_recording = valid_access_recording(recording)
        service = RevokeRecordingAccess.new(recording: recording, access_recording: access_recording,
                                            manager_actor: :manager)

        service.stub(:valid_access_recording_for_parent?, true) do
          service.stub(:destroy_access_recording!, true) do
            result = service.send(:perform)

            assert result.success?
            assert_equal true, result.value
          end
        end
      end

      private

      class RootRecorder
        AccessDouble = Struct.new(:actor, :role)

        attr_reader :record_calls, :revise_calls

        def initialize(return_value)
          @return_value = return_value
          @record_calls = []
          @revise_calls = []
        end

        def record(recordable_class, actor:, parent_recording:)
          access = AccessDouble.new
          yield access
          @record_calls << [recordable_class, actor, parent_recording, access.actor, access.role]
          @return_value
        end

        def revise(access_recording, actor:)
          access = AccessDouble.new
          yield access
          @revise_calls << [access_recording, actor, access.role]
          @return_value
        end
      end

      def valid_access_recording(recording)
        Recording.new(id: 2, parent_recording_id: recording.id, recordable_type: "RecordingStudio::Access",
                      root_id: recording.root_id)
      end

      def ensure_recording_class!
        return if RecordingStudio.const_defined?(:Recording, false)

        @created_recording_class = true
        RecordingStudio.const_set(:Recording, Class.new do
          def self.transaction
            yield
          end

          def self.none = []
        end)
      end

      def ensure_access_class!
        return if RecordingStudio.const_defined?(:Access, false)

        @created_access_class = true
        RecordingStudio.const_set(:Access, Class.new do
          def self.roles
            { "view" => 0, "edit" => 1, "admin" => 2 }
          end
        end)
      end

      def ensure_active_record_error_class!
        return if Object.const_defined?(:ActiveRecord, false)

        @created_active_record_module = true
        Object.const_set(:ActiveRecord, Module.new do
          const_set(:RecordInvalid, Class.new(StandardError) do
            attr_reader :record

            def initialize(record = nil)
              @record = record
              super("Record invalid")
            end
          end)
        end)
      end
    end
  end
end
