# frozen_string_literal: true

require_relative "configuration/call_helpers"

module RecordingStudioAccessible
  # An admin holds a role on the recording from admin_root_resolver.
  module AdminRoot
    include Configuration::CallHelpers

    def admin_root(context: {})
      resolved = invoke_admin_root_resolver(context)
      return unless accepted_admin_root?(resolved)

      resolved
    rescue StandardError => e
      warn_admin_failure("admin_root_resolver", e)
      nil
    end

    def admin?(actor:, role: :view, context: {})
      return false if actor.nil?

      root = admin_root(context: context)
      return false if root.nil?
      return false unless role_valid_for?(root, role)
      return true if authorized?(actor: actor, recording: root, role: role)

      false
    rescue StandardError => e
      warn_admin_failure("admin?", e)
      false
    end

    private

    def invoke_admin_root_resolver(context)
      callable = configuration.admin_root_resolver
      return unless callable.respond_to?(:call)

      callable.call(**filtered_keyword_arguments(callable, context: context))
    end

    def accepted_admin_root?(recording)
      recording.is_a?(RecordingStudio::Recording) &&
        recording.parent_recording_id.nil? &&
        kept_admin_root?(recording)
    end

    def kept_admin_root?(recording)
      recording.id.present? && RecordingStudio::Recording.kept.where(id: recording.id).exists?
    end

    def warn_admin_failure(source, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[RecordingStudioAccessible] #{source} failed: #{error.class}: #{error.message}")
    end
  end
end
