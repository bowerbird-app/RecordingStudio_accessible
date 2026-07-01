# frozen_string_literal: true

require "test_helper"

class AuthorizationServiceTest < Minitest::Test
  def test_returns_false_for_allowed_check_without_actor
    result = RecordingStudioAccessible::AuthorizationService.call(actor: nil, recording: :recording, role: :view)

    assert result.success?
    refute result.value
  end

  def test_returns_nil_role_without_actor
    result = RecordingStudioAccessible::AuthorizationService.call(actor: nil, recording: :recording)

    assert result.success?
    assert_nil result.value
  end

  def test_returns_resolved_role_as_symbol
    resolver = resolver_returning("edit")

    RecordingStudio::Services::AccessResolver.stub(:new, resolver) do
      result = RecordingStudioAccessible::AuthorizationService.call(actor: :actor, recording: :recording)

      assert result.success?
      assert_equal :edit, result.value
    end
  end

  def test_checks_role_requirement_against_resolved_role
    resolver = resolver_returning("edit")

    RecordingStudio::Services::AccessResolver.stub(:new, resolver) do
      assert RecordingStudioAccessible::AuthorizationService.call(actor: :actor, recording: :recording,
                                                                  role: :view).value
      refute RecordingStudioAccessible::AuthorizationService.call(actor: :actor, recording: :recording,
                                                                  role: :admin).value
    end
  end

  private

  def resolver_returning(role)
    lambda do |actor:, recording:|
      assert_equal :actor, actor
      assert_equal :recording, recording
      Object.new.tap do |resolver|
        resolver.define_singleton_method(:resolve_role) { role }
      end
    end
  end
end
