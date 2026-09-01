# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class VoidDependentAccessesTest < Minitest::Test
      def setup
        ensure_recording_class!
      end

      def teardown
        RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
      end

      def test_returns_success_with_empty_list_without_a_manager_id
        result = VoidDependentAccesses.call(manager_access_recording_id: nil)

        assert result.success?
        assert_equal [], result.value
      end

      def test_destroys_dependents_that_are_no_longer_effective
        dependent = Object.new
        dependent.define_singleton_method(:id) { 7 }
        service = VoidDependentAccesses.new(manager_access_recording_id: "manager-id")
        destroyed = []

        relation = Object.new
        relation.define_singleton_method(:find_each) { |&block| [dependent].each(&block) }

        RecordingStudio::Recording.stub(:transaction, ->(&block) { block.call }) do
          RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_depending_on, relation) do
            RecordingStudioAccessible::DependentAccess.stub(:effective?, false) do
              service.stub(:destroy_access_recording!, lambda { |access_recording, manager_actor:|
                destroyed << [access_recording, manager_actor]
              }) do
                result = service.send(:perform)

                assert result.success?
                assert_equal [7], result.value
                assert_equal [[dependent, nil]], destroyed
              end
            end
          end
        end
      end

      def test_leaves_dependents_that_are_still_effective
        dependent = Object.new
        dependent.define_singleton_method(:id) { 7 }
        service = VoidDependentAccesses.new(manager_access_recording_id: "manager-id")

        relation = Object.new
        relation.define_singleton_method(:find_each) { |&block| [dependent].each(&block) }

        RecordingStudio::Recording.stub(:transaction, ->(&block) { block.call }) do
          RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_depending_on, relation) do
            RecordingStudioAccessible::DependentAccess.stub(:effective?, true) do
              service.stub(:destroy_access_recording!, ->(*) { flunk "should not void an effective grant" }) do
                result = service.send(:perform)

                assert result.success?
                assert_equal [], result.value
              end
            end
          end
        end
      end

      def test_returns_failure_when_voiding_raises
        service = VoidDependentAccesses.new(manager_access_recording_id: "manager-id")

        RecordingStudio::Recording.stub(:transaction, ->(*) { raise "boom" }) do
          result = service.send(:perform)

          assert result.failure?
          assert_equal "boom", result.error
        end
      end

      def test_job_delegates_to_the_void_service
        called = nil

        VoidDependentAccesses.stub(:call, lambda { |**kwargs|
          called = kwargs
          :ok
        }) do
          RecordingStudioAccessible::VoidDependentAccessesJob.perform_now("manager-id")
        end

        assert_equal({ manager_access_recording_id: "manager-id" }, called)
      end

      private

      def ensure_recording_class!
        return if RecordingStudio.const_defined?(:Recording, false)

        @created_recording_class = true
        RecordingStudio.const_set(:Recording, Class.new do
          def self.transaction
            yield
          end
        end)
      end
    end
  end
end
