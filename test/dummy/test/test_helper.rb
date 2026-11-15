ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "devise/test/integration_helpers"

ActionController::Base.allow_forgery_protection = false

module RecordingWriteActor
  module_function

  # Core 7 requires an actor on every write. The dummy does not set
  # allow_unauthorized_writes. Prefer the request actor, then a user the
  # test already created, and only then a writer row.
  def resolve
    current = defined?(Current) ? Current.actor : nil
    return current if current.present?
    return unless defined?(User)

    User.order(:created_at, :id).first ||
      User.create!(
        email: "recording-writer@example.com",
        password: "Password",
        password_confirmation: "Password"
      )
  end
end

module RecordingStudioAccessibleTestHelpers
  def create_root_recording(recordable)
    RecordingStudio.create_root_recording!(
      recordable,
      actor: RecordingWriteActor.resolve,
      impersonator: nil,
      metadata: {}
    )
  end

  def create_child_recording(recordable:, parent_recording:)
    RecordingStudio.root_recording_or_self(parent_recording).record(
      recordable,
      parent_recording: parent_recording,
      actor: RecordingWriteActor.resolve
    )
  end

  def create_direct_access_recording(actor:, role:, parent_recording:)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(parent_recording).record(
        RecordingStudio::Access,
        parent_recording: parent_recording,
        actor: RecordingWriteActor.resolve
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end
end

RecordingStudio.configuration.actor = -> { RecordingWriteActor.resolve }

ActiveSupport::TestCase.include RecordingStudioAccessibleTestHelpers

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include RecordingStudioAccessibleTestHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36".freeze

  def before_setup
    super
    host! "localhost"
    Rails.cache.clear
  end

  %i[get post patch put delete head].each do |http_method|
    define_method(http_method) do |path, **args|
      headers = args.fetch(:headers, {}).dup
      headers["User-Agent"] ||= MODERN_USER_AGENT

      super(path, **args.merge(headers: headers))
    end
  end
end
