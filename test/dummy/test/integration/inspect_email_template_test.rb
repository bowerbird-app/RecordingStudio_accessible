require "test_helper"

class InspectEmailTemplateTest < ActionDispatch::IntegrationTest
  test "inspect email template rendered page" do
    u = User.find_by(email: "admin@admin.com")
    puts "User exists? #{u.present?}"
    sign_in u if u

    get "/recording_studio_accessible/email_template"
    puts "Response Code: #{response.code}"

    html = response.body
    puts "--- HTML BEGIN ---"
    puts html
    puts "--- HTML END ---"
  end
end
