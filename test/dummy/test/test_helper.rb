ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "rails/test_help"
require "devise/test/integration_helpers"

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
