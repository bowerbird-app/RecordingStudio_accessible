# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class VoidDependentAccessesTest < Minitest::Test
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
    end
  end
end
