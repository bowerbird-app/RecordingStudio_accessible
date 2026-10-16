# frozen_string_literal: true

module RecordingStudioAccessible
  # Allowed manager moves among pending, approved, and denied.
  module AccessRequestTransitions
    STATUSES = %w[pending approved denied].freeze
    ALLOWED = {
      "pending" => %w[approved denied].freeze,
      "approved" => %w[pending denied].freeze,
      "denied" => %w[pending approved].freeze
    }.freeze
    HOOKS = {
      "pending" => :access_request_reopened,
      "approved" => :access_request_approved,
      "denied" => :access_request_denied
    }.freeze
    EVENTS = {
      "pending" => "reopened",
      "approved" => "approved",
      "denied" => "denied"
    }.freeze
    FLASHES = {
      "pending" => "reopened",
      "approved" => "approved",
      "denied" => "denied"
    }.freeze

    module_function

    def allowed?(from:, to:)
      ALLOWED.fetch(from.to_s, []).include?(to.to_s)
    end

    def targets_for(from)
      ALLOWED.fetch(from.to_s, [])
    end

    def hook_for(status)
      HOOKS.fetch(status.to_s)
    end

    def event_for(status)
      EVENTS.fetch(status.to_s)
    end

    def flash_key(status)
      FLASHES[status.to_s]
    end
  end
end
