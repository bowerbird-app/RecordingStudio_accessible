# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < Minitest::Test
  AuthorizationServiceStub = Class.new do
    class << self
      attr_reader :allowed_call, :role_call

      def reset!
        @allowed_call = nil
        @role_call = nil
      end

      def allowed?(**kwargs)
        @allowed_call = kwargs
        true
      end

      def role_for(**kwargs)
        @role_call = kwargs
        :edit
      end
    end
  end

  def setup
    AuthorizationServiceStub.reset!
  end

  def test_module_level_authorization_api_delegates_to_compatibility_service
    RecordingStudioAccessible::Compatibility.stub(:authorization_service, AuthorizationServiceStub) do
      assert_equal :edit, RecordingStudioAccessible.role_for(actor: :actor, recording: :recording)
      assert RecordingStudioAccessible.authorized?(actor: :actor, recording: :recording, role: :admin)
      assert RecordingStudioAccessible::Authorization.allowed?(actor: :actor, recording: :recording, role: :view)
    end

    assert_equal({ actor: :actor, recording: :recording }, AuthorizationServiceStub.role_call)
    assert_equal({ actor: :actor, recording: :recording, role: :view }, AuthorizationServiceStub.allowed_call)
  end

  def test_authorization_api_fails_closed_without_compatibility_service
    RecordingStudioAccessible::Compatibility.stub(:authorization_service, nil) do
      assert_nil RecordingStudioAccessible.role_for(actor: :actor, recording: :recording)
      refute RecordingStudioAccessible.authorized?(actor: :actor, recording: :recording, role: :admin)
      refute RecordingStudioAccessible::Authorization.allowed?(actor: :actor, recording: :recording, role: :view)
    end
  end
end
