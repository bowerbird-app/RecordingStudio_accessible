# frozen_string_literal: true

require "test_helper"

class TailwindThemeTest < ActiveSupport::TestCase
  test "tailwind entry leaves rounded theme tokens to flatpack" do
    css = Rails.root.join("app/assets/tailwind/application.css").read

    refute_match(/--color-primary\s*:/, css)
    refute_match(/--color-fp-/, css)
    refute_match(/--radius-md\s*:/, css)
    assert_match(/data-theme="rounded"/, css)
  end
end
