# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module OpenapiSchemas
      ACTOR = {
        type: "object",
        required: %w[id type label],
        properties: {
          id: {},
          type: { type: "string" },
          label: { type: "string" }
        }
      }.freeze

      RECORDING = {
        type: "object",
        required: %w[id type label],
        properties: {
          id: {},
          type: { type: "string" },
          label: { type: "string" }
        }
      }.freeze

      DIRECT_GRANT = {
        type: "object",
        required: %w[invited inherited role effective_role actor source_recording notice],
        properties: {
          invited: { type: "boolean", enum: [false] },
          inherited: { type: "boolean", enum: [false] },
          role: { type: "string" },
          effective_role: { type: "string" },
          actor: ACTOR,
          source_recording: RECORDING,
          notice: { type: "string" }
        }
      }.freeze

      PENDING_INVITATION = {
        type: "object",
        required: %w[invited email role notice],
        properties: {
          invited: { type: "boolean", enum: [true] },
          email: { type: "string" },
          role: { type: "string" },
          notice: { type: "string" }
        }
      }.freeze

      GRANT_ROW = {
        type: "object",
        required: %w[inherited role effective_role actor source_recording status],
        properties: {
          inherited: { type: "boolean" },
          role: { type: "string" },
          effective_role: { type: "string" },
          actor: ACTOR,
          source_recording: RECORDING,
          status: { type: "string", enum: %w[granted] }
        }
      }.freeze

      INVITATION_ROW = {
        type: "object",
        required: %w[inherited role email source_recording status],
        properties: {
          inherited: { type: "boolean", enum: [false] },
          role: { type: "string" },
          email: { type: "string" },
          source_recording: RECORDING,
          status: { type: "string", enum: %w[pending expired] }
        }
      }.freeze

      REVOKE_ACCESS = {
        type: "object",
        required: %w[revoked actor],
        properties: {
          revoked: { type: "boolean" },
          actor: ACTOR
        }
      }.freeze

      UPDATE_ACCESS = {
        type: "object",
        required: %w[invited inherited role effective_role actor source_recording],
        properties: {
          invited: { type: "boolean", enum: [false] },
          inherited: { type: "boolean", enum: [false] },
          role: { type: "string" },
          effective_role: { type: "string" },
          actor: ACTOR,
          source_recording: RECORDING
        }
      }.freeze
    end
  end
end
