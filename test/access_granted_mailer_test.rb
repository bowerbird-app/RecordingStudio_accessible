# frozen_string_literal: true

require "test_helper"

class AccessGrantedMailerTest < Minitest::Test
  RecipientStub = Struct.new(:email, keyword_init: true)
  ManagerActorStub = Struct.new(:email, :full_name, :name, :display_name, keyword_init: true)

  def setup
    RecordingStudioAccessible::AccessGrantedMailer.prepend_view_path(File.expand_path("../app/views", __dir__))
  end

  def test_access_granted_prefers_full_name_for_manager_display
    message = build_message(
      manager_actor: ManagerActorStub.new(email: "admin@admin.com", full_name: "Alice Smith")
    )

    assert_includes message.html_part.decoded, "Alice Smith"
    assert_includes message.text_part.decoded, "Alice Smith granted you view access."
  end

  def test_access_granted_humanizes_manager_email_when_name_is_missing
    message = build_message(
      manager_actor: ManagerActorStub.new(email: "admin@admin.com")
    )

    assert_includes message.html_part.decoded, "Admin"
    assert_includes message.text_part.decoded, "Admin granted you view access."
  end

  private

  def build_message(manager_actor:)
    RecordingStudioAccessible::AccessGrantedMailer.with(
      actor: RecipientStub.new(email: "viewer@example.com"),
      role: :view,
      manager_actor: manager_actor,
      access_url: "http://example.test/workspaces/123",
      subject: "You were given access"
    ).access_granted.message
  end
end
