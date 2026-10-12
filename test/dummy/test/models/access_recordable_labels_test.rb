# frozen_string_literal: true

require_relative "../test_helper"

class AccessRecordableLabelsTest < ActiveSupport::TestCase
  test "access recordable labels keep English constants and resolve at call time" do
    assert_equal "Access", RecordingStudio::Access::LABEL
    assert_equal "Audience", RecordingStudio::AccessRule::LABEL
    assert_equal "Audience limit", RecordingStudio::AccessConstraint::LABEL

    I18n.with_locale(:en) do
      assert_equal "Access", RecordingStudio::Access.recordable_type_label
      assert_equal "Audience", RecordingStudio::AccessRule.recordable_type_label
      assert_equal "Audience limit", RecordingStudio::AccessConstraint.recordable_type_label
      assert_equal RecordingStudio::AccessRule::WRITE_ERROR, RecordingStudio::AccessRule.audience_write_error
    end
  end

  test "access recordable labels follow a non-English locale while constants stay English" do
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.with_locale(:fr) do
      assert_equal "Access", RecordingStudio::Access::LABEL
      assert_equal "Accès", RecordingStudio::Access.recordable_type_label
      assert_equal "Audience", RecordingStudio::AccessRule.recordable_type_label
      assert_equal "Limite d’audience", RecordingStudio::AccessConstraint.recordable_type_label
      assert_equal(
        "Créez les audiences via RecordingStudioAccessible.set_audience!",
        RecordingStudio::AccessRule.audience_write_error
      )
    end
  end

  test "access recordable_name uses translated unknown actor fallback" do
    access = RecordingStudio::Access.new(role: "view", actor: nil)

    I18n.with_locale(:fr) do
      assert_equal "Accès : view — Personne inconnue", access.recordable_name
    end
  end
end
