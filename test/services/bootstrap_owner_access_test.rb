# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class BootstrapOwnerAccessTest < Minitest::Test
      Recording = Struct.new(:id, :recordable_type, :persisted, keyword_init: true) do
        attr_reader :locked

        def persisted? = persisted != false

        def lock! = @locked = true
      end
      Actor = Struct.new(:id, :persisted, keyword_init: true) do
        def self.base_class = self

        def persisted? = persisted != false
      end

      def setup
        ensure_recording_class!
        ensure_access_class!
        ensure_active_record_error_class!
        @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
        RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
        RecordingStudioAccessible.configuration.access_actor_types = [Actor]
      end

      def teardown
        RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
        RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
        RecordingStudio.send(:remove_const, :Access) if @created_access_class
        Object.send(:remove_const, :ActiveRecord) if @created_active_record_module
      end

      def test_validates_required_and_persisted_inputs
        actor = Actor.new(id: 1)
        recording = Recording.new(id: 1, recordable_type: "Workspace")

        assert_equal "Recording is required",
                     BootstrapOwnerAccess.call(recording: nil, actor: actor).error
        assert_equal BootstrapOwnerAccess::RECORDING_NOT_PERSISTED_MESSAGE,
                     BootstrapOwnerAccess.call(recording: Recording.new(id: 1, persisted: false), actor: actor).error
        assert_equal "Actor is required",
                     BootstrapOwnerAccess.call(recording: recording, actor: nil).error
        assert_equal BootstrapOwnerAccess::ACTOR_NOT_PERSISTED_MESSAGE,
                     BootstrapOwnerAccess.call(recording: recording, actor: Actor.new(id: 1, persisted: false)).error
      end

      def test_rejects_owned_root_children_shared_roots_and_disallowed_targets
        recording = Recording.new(id: 1, recordable_type: "Workspace")
        actor = Actor.new(id: 1)

        RecordingStudio.stub(:root_recording?, false) do
          RecordingStudio.stub(:shared_root_tree?, false) do
            RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
              assert_equal BootstrapOwnerAccess::UNSUPPORTED_RECORDING_MESSAGE,
                           BootstrapOwnerAccess.call(recording: recording, actor: actor).error
            end
          end
        end

        RecordingStudio.stub(:root_recording?, true) do
          RecordingStudioAccessible::SharedRootAccess.stub(:target?, true) do
            assert_equal SharedRootAccess::GRANT_DENIED_MESSAGE,
                         BootstrapOwnerAccess.call(recording: recording, actor: actor).error
          end

          RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
            RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, false) do
              assert_equal "Direct access is not enabled for this recording",
                           BootstrapOwnerAccess.call(recording: recording, actor: actor).error
            end

            RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, true) do
              RecordingStudioAccessible.configuration.access_actor_types = [String]
              assert_equal "Actor type is not allowed for access",
                           BootstrapOwnerAccess.call(recording: recording, actor: actor).error
            end
          end
        end
      end

      def test_profile_shaped_shared_forest_child_is_not_rejected_as_non_root
        refute BootstrapOwnerAccess.const_defined?(:NON_ROOT_MESSAGE)
        assert_includes BootstrapOwnerAccess.included_modules, AccessGrantWriter

        # 0.6.1 reproduction: Profile under People (same shape as dummy
        # MessageGroup under MessageRoot). root_recording? false, shared_root?
        # false, then NON_ROOT_MESSAGE before shared-root denial.
        %w[Profile MessageGroup].each do |recordable_type|
          recording = Recording.new(id: 2, recordable_type: recordable_type)
          actor = Actor.new(id: 1)
          service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

          RecordingStudio.stub(:root_recording?, false) do
            RecordingStudio.stub(:shared_root?, false) do
              RecordingStudio.stub(:shared_root_tree?, true) do
                RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
                  RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, true) do
                    result = service.send(:validate_request)

                    refute_equal "Recording must be a root recording",
                                 result.respond_to?(:error) ? result.error : nil
                    assert_equal true, result
                  end
                end
              end
            end
          end
        end
      end

      def test_shared_forest_child_via_root_when_recording_is_not_the_root
        recording = Recording.new(id: 2, recordable_type: "MessageGroup")
        actor = Actor.new(id: 1)
        root = Recording.new(id: 1, recordable_type: "MessageRoot")
        service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

        RecordingStudio.stub(:root_recording_or_self, root) do
          RecordingStudioAccessible::SharedRootAccess.stub(:target?, true) do
            assert service.send(:shared_forest_child_via_root?)
          end
        end
      end

      def test_rejects_shared_forest_child_without_accessible
        recording = Recording.new(id: 2, recordable_type: "MessageGroup")
        actor = Actor.new(id: 1)

        RecordingStudio.stub(:root_recording?, false) do
          RecordingStudio.stub(:shared_root_tree?, true) do
            RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
              RecordingStudioAccessible::Compatibility.stub(:access_management_allowed?, false) do
                assert_equal "Direct access is not enabled for this recording",
                             BootstrapOwnerAccess.call(recording: recording, actor: actor).error
              end
            end
          end
        end
      end

      def test_perform_creates_admin_grant_when_empty
        recording = Recording.new(id: 1, recordable_type: "Workspace")
        actor = Actor.new(id: 1)
        service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:active_direct_access_holders, []) do
              service.stub(:create_access_recording, :created_access) do
                result = service.send(:perform)

                assert result.success?
                assert_equal :created_access, result.value
                assert recording.locked
              end
            end
          end
        end
      end

      def test_perform_is_idempotent_when_only_existing_grant_is_self_admin
        recording = Recording.new(id: 1, recordable_type: "Workspace")
        actor = Actor.new(id: 1)
        access = Struct.new(:actor, :role).new(actor, "admin")
        existing = Struct.new(:recordable).new(access)
        service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:active_direct_access_holders, [existing]) do
              result = service.send(:perform)

              assert result.success?
              assert_equal existing, result.value
            end
          end
        end
      end

      def test_perform_fails_when_another_holder_exists
        recording = Recording.new(id: 1, recordable_type: "Workspace")
        actor = Actor.new(id: 1)
        other = Actor.new(id: 2)
        access = Struct.new(:actor, :role).new(other, "admin")
        existing = Struct.new(:recordable).new(access)
        service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:active_direct_access_holders, [existing]) do
              result = service.send(:perform)

              assert result.failure?
              assert_equal BootstrapOwnerAccess::ALREADY_BOOTSTRAPPED_MESSAGE, result.error
            end
          end
        end
      end

      def test_perform_fails_when_only_holder_is_self_but_not_admin
        recording = Recording.new(id: 1, recordable_type: "Workspace")
        actor = Actor.new(id: 1)
        access = Struct.new(:actor, :role).new(actor, "view")
        existing = Struct.new(:recordable).new(access)
        service = BootstrapOwnerAccess.new(recording: recording, actor: actor)

        service.stub(:validate_request, true) do
          service.stub(:ensure_current_impersonator_accessor!, nil) do
            service.stub(:active_direct_access_holders, [existing]) do
              result = service.send(:perform)

              assert result.failure?
              assert_equal BootstrapOwnerAccess::ALREADY_BOOTSTRAPPED_MESSAGE, result.error
            end
          end
        end
      end

      def test_public_facade_delegates_to_service
        called = nil
        BootstrapOwnerAccess.stub(:call, lambda { |**kwargs|
          called = kwargs
          BaseService::Result.new(success: true, value: :ok)
        }) do
          result = RecordingStudioAccessible.bootstrap_owner_access!(
            recording: :recording,
            actor: :actor
          )

          assert result.success?
          assert_equal({ recording: :recording, actor: :actor }, called)
        end
      end

      private

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
