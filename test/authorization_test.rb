# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < Minitest::Test
  AuthorizationServiceStub = Class.new do
    class << self
      attr_reader :allowed_call, :role_call, :root_recordings_call, :root_recording_ids_call, :access_recordings_call

      def reset!
        @allowed_call = nil
        @role_call = nil
        @root_recordings_call = nil
        @root_recording_ids_call = nil
        @access_recordings_call = nil
      end

      def allowed?(**kwargs)
        @allowed_call = kwargs
        true
      end

      def role_for(**kwargs)
        @role_call = kwargs
        :edit
      end

      def root_recordings_for(**kwargs)
        @root_recordings_call = kwargs
        [:recording]
      end

      def root_recording_ids_for(**kwargs)
        @root_recording_ids_call = kwargs
        [123]
      end

      def access_recordings_for(recording)
        @access_recordings_call = recording
        [:grant]
      end
    end
  end

  def setup
    AuthorizationServiceStub.reset!
  end

  def test_module_level_authorization_api_delegates_to_authorization_service
    RecordingStudioAccessible::Authorization.stub(:authorization_service, AuthorizationServiceStub) do
      assert_equal :edit, RecordingStudioAccessible.role_for(actor: :actor, recording: :recording)
      assert RecordingStudioAccessible.authorized?(actor: :actor, recording: :recording, role: :admin)
      assert RecordingStudioAccessible::Authorization.allowed?(actor: :actor, recording: :recording, role: :view)
      assert_equal [:recording], RecordingStudioAccessible.root_recordings_for(actor: :actor, minimum_role: :view)
      assert_equal [123], RecordingStudioAccessible.root_recording_ids_for(actor: :actor, minimum_role: :edit)
      assert_equal [:grant], RecordingStudioAccessible.access_recordings_for(:recording)
    end

    assert_equal({ actor: :actor, recording: :recording }, AuthorizationServiceStub.role_call)
    assert_equal({ actor: :actor, recording: :recording, role: :view }, AuthorizationServiceStub.allowed_call)
    assert_equal({ actor: :actor, minimum_role: :view }, AuthorizationServiceStub.root_recordings_call)
    assert_equal({ actor: :actor, minimum_role: :edit }, AuthorizationServiceStub.root_recording_ids_call)
    assert_equal :recording, AuthorizationServiceStub.access_recordings_call
  end
end
