# frozen_string_literal: true

require "test_helper"

class InspectEmailTemplateTest < ActionDispatch::IntegrationTest
  test "inspect email template rendered page" do
    post "/users/sign_in", params: { user: { email: "admin@admin.com", password: "Password" } }
    get "/recording_studio_accessible/email_template"

    html = response.body
    puts "--- START INSPECTION DATA ---"
    has_anchor = html.match?(%r{<a[^>]*Open the shared item[^<]*</a>})
    puts "HAS_ANCHOR: #{has_anchor}"

    snippet = html.match(%r{<a[^>]*Open the shared item[^<]*</a>}).to_s
    puts "SNIPPET: #{snippet}"

    # Check for the URL in something that looks like a text preview
    has_plain_url = html.scan(%r{https?://[^\s<]+}).any? { |url| url.include?("recording") }
    puts "HAS_PLAIN_URL: #{has_plain_url}"
    puts "--- END INSPECTION DATA ---"
  end
end
