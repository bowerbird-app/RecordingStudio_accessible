# frozen_string_literal: true

require "test_helper"

class AccessGrantedMailerLabelTest < Minitest::Test
  def test_display_label_for_humanizes_email_when_name_methods_are_blank
    actor = Struct.new(:full_name, :name, :display_name, :email).new(nil, "", nil, "ada.lovelace@example.com")

    assert_equal "Ada Lovelace", RecordingStudioAccessible::AccessGrantedMailer.display_label_for(actor)
  end

  def test_recordable_label_returns_nil_without_recordable
    recording = Struct.new(:recordable).new(nil)

    assert_nil RecordingStudioAccessible::AccessGrantedMailer.recordable_label_for(recording)
  end
end
