# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < Minitest::Test
  AuthorizationServiceStub = Class.new do
    class << self
      attr_reader :allowed_call, :role_call, :allowed_through_call, :role_through_call, :root_recordings_call,
                  :root_recording_ids_call, :access_recordings_call, :recordings_calls, :recording_ids_calls

      def reset!
        @allowed_call = nil
        @role_call = nil
        @allowed_through_call = nil
        @role_through_call = nil
        @root_recordings_call = nil
        @root_recording_ids_call = nil
        @access_recordings_call = nil
        @recordings_calls = []
        @recording_ids_calls = []
      end

      def allowed?(**kwargs)
        @allowed_call = kwargs
        true
      end

      def role_for(**kwargs)
        @role_call = kwargs
        :edit
      end

      def allowed_through?(**kwargs)
        @allowed_through_call = kwargs
        true
      end

      def role_through(**kwargs)
        @role_through_call = kwargs
        :admin
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

      def recordings_for(**kwargs)
        @recordings_calls << kwargs
        :children
      end

      def recording_ids_for(**kwargs)
        @recording_ids_calls << kwargs
        [7]
      end
    end
  end

  def setup
    AuthorizationServiceStub.reset!
  end

  def test_module_level_authorization_api_delegates_to_authorization_service
    execute_module_level_authorization_api_delegation
    verify_module_level_authorization_api_delegation_stubs
  end

  private

  def execute_module_level_authorization_api_delegation
    RecordingStudioAccessible::Authorization.stub(:authorization_service, AuthorizationServiceStub) do
      assert_equal :edit, RecordingStudioAccessible.role_for(actor: :actor, recording: :recording)
      assert RecordingStudioAccessible.authorized?(actor: :actor, recording: :recording, role: :admin)
      assert_equal :admin, RecordingStudioAccessible.role_through(actor: :actor, through: :through, recording: :recording, controller: :controller)
      assert RecordingStudioAccessible.authorized_through?(actor: :actor, through: :through, recording: :recording, role: :admin, controller: :controller)
      assert RecordingStudioAccessible::Authorization.allowed?(actor: :actor, recording: :recording, role: :view)
      assert RecordingStudioAccessible::Authorization.allowed_through?(actor: :actor, through: :through, recording: :recording, role: :view, controller: :controller)
      assert_equal [:recording], RecordingStudioAccessible.root_recordings_for(actor: :actor, minimum_role: :view)
      assert_equal [123], RecordingStudioAccessible.root_recording_ids_for(actor: :actor, minimum_role: :edit)
      assert_equal [:grant], RecordingStudioAccessible.access_recordings_for(:recording)
      assert_equal :children, RecordingStudioAccessible.recordings_for(**recordings_for_keywords)
      assert_equal [7], RecordingStudioAccessible.recording_ids_for(**recording_ids_keywords)
      assert_equal :children, RecordingStudioAccessible::Authorization.recordings_for(**recordings_for_keywords)
      assert_equal [7], RecordingStudioAccessible::Authorization.recording_ids_for(**recording_ids_keywords)
    end
  end

  def verify_module_level_authorization_api_delegation_stubs
    assert_equal({ actor: :actor, recording: :recording }, AuthorizationServiceStub.role_call)
    assert_equal({ actor: :actor, recording: :recording, role: :view }, AuthorizationServiceStub.allowed_call)
    assert_equal(
      { actor: :actor, through: :through, recording: :recording, controller: :controller },
      AuthorizationServiceStub.role_through_call
    )
    assert_equal(
      { actor: :actor, through: :through, recording: :recording, role: :view, controller: :controller },
      AuthorizationServiceStub.allowed_through_call
    )
    assert_equal({ actor: :actor, minimum_role: :view }, AuthorizationServiceStub.root_recordings_call)
    assert_equal({ actor: :actor, minimum_role: :edit }, AuthorizationServiceStub.root_recording_ids_call)
    assert_equal :recording, AuthorizationServiceStub.access_recordings_call
    assert_equal [recordings_for_keywords, recordings_for_keywords], AuthorizationServiceStub.recordings_calls
    assert_equal [recording_ids_keywords, recording_ids_keywords], AuthorizationServiceStub.recording_ids_calls
  end

  def recordings_for_keywords
    { actor: :actor, parent_recording: :parent, minimum_role: :view, recordable_type: "MessageGroup" }
  end

  def recording_ids_keywords
    { actor: :actor, parent_recording: :parent, minimum_role: :edit, recordable_type: "Page" }
  end
end
