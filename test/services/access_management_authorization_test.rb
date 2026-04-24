# frozen_string_literal: true

require "test_helper"

module RecordingStudioAccessible
  module Services
    class AccessManagementAuthorizationTest < Minitest::Test
      RecordingStub = Struct.new(:id)
      AccessRecordingStub = Struct.new(:id)

      def setup
        @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
        configuration = RecordingStudioAccessible::Configuration.new
        configuration.access_management_authorizer = ->(**) { false }
        RecordingStudioAccessible.instance_variable_set(:@configuration, configuration)
      end

      def teardown
        RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
      end

      def test_grant_recording_access_requires_authorized_manager_actor
        result = GrantRecordingAccess.call(
          recording: RecordingStub.new("recording-1"),
          actor: nil,
          role: "view",
          manager_actor: nil
        )

        refute result.success?
        assert_equal "Not authorized to manage access", result.error
      end

      def test_update_recording_access_requires_authorized_manager_actor
        result = UpdateRecordingAccess.call(
          recording: RecordingStub.new("recording-1"),
          access_recording: AccessRecordingStub.new("access-recording-1"),
          role: "edit",
          manager_actor: nil
        )

        refute result.success?
        assert_equal "Not authorized to manage access", result.error
      end

      def test_revoke_recording_access_requires_authorized_manager_actor
        result = RevokeRecordingAccess.call(
          recording: RecordingStub.new("recording-1"),
          access_recording: AccessRecordingStub.new("access-recording-1"),
          manager_actor: nil
        )

        refute result.success?
        assert_equal "Not authorized to manage access", result.error
      end
    end
  end
end
