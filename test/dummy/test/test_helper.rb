ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "devise/test/integration_helpers"

ActionController::Base.allow_forgery_protection = false

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36".freeze

  def before_setup
    super
    host! "localhost"
  end

  %i[get post patch put delete head].each do |http_method|
    define_method(http_method) do |path, **args|
      headers = args.fetch(:headers, {}).dup
      headers["User-Agent"] ||= MODERN_USER_AGENT

      super(path, **args.merge(headers: headers))
    end
  end
end
