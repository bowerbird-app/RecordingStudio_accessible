# frozen_string_literal: true

require_relative "access_request_decision_forms"

module RecordingStudioAccessible
  module AccessRequestDecisionsHelper
    include AccessRequestDecisionForms

    DECISIONS = %w[approved denied].freeze

    def access_request_actions_cell(request_recording, page:, list_url:)
      safe_join([
                  access_request_decision_buttons(request_recording),
                  access_request_decision_modals(request_recording, page, list_url),
                  access_request_cursor_marker(request_recording)
                ])
    end

    private

    def access_request_decision_buttons(request_recording)
      statuses = access_request_decision_statuses(request_recording)
      tag.div(class: "flex flex-wrap items-center gap-2") do
        safe_join(statuses.map { |status| access_request_decision_button(request_recording, status) })
      end
    end

    def access_request_decision_statuses(request_recording)
      AccessRequestTransitions.targets_for(request_recording.recordable.status) & DECISIONS
    end

    def access_request_decision_button(request_recording, status)
      render FlatPack::Button::Component.new(**access_request_decision_button_args(request_recording, status))
    end

    def access_request_decision_button_args(request_recording, status)
      {
        text: access_request_decision_label(status),
        style: status == "approved" ? :primary : :default,
        size: :sm,
        type: "button",
        data: { modal_id: access_request_modal_id(request_recording, status) }
      }
    end

    def access_request_modal_id(request_recording, status)
      "access-request-#{status}-#{request_recording.id}"
    end

    def access_request_decision_modals(request_recording, page, list_url)
      statuses = access_request_decision_statuses(request_recording)
      safe_join(statuses.map { |status| access_request_decision_modal(request_recording, status, page, list_url) })
    end

    def access_request_decision_modal(request_recording, status, page, list_url)
      render FlatPack::Modal::Component.new(**access_request_modal_args(request_recording, status)) do |modal|
        modal.body { concat access_request_decision_body(request_recording, status, page, list_url) }
      end
    end

    def access_request_modal_args(request_recording, status)
      { id: access_request_modal_id(request_recording, status), title: access_request_decision_label(status),
        size: :md }
    end

    def access_request_decision_body(request_recording, status, page, list_url)
      safe_join([
        access_request_decision_context(request_recording),
        access_request_decision_form(request_recording, status, page, list_url)
      ].compact)
    end

    def access_request_decision_context(request_recording)
      parts = access_request_context_parts(request_recording)
      return if parts.empty?

      tag.div(class: "mb-6 grid gap-3") { safe_join(parts) }
    end

    def access_request_context_parts(request_recording)
      record = request_recording.recordable
      [access_request_context_note(record), *access_request_context_answers(record)].compact
    end

    def access_request_context_note(record)
      return if record.message.blank?

      tag.p(record.message)
    end

    def access_request_context_answers(record)
      access_request_gate_answers(record).map { |label, value| access_request_context_answer(label, value) }
    end

    def access_request_context_answer(label, value)
      tag.div do
        safe_join([
                    tag.p(label, class: "text-sm text-[var(--surface-muted-content-color)]"),
                    tag.p(value, class: "mt-1")
                  ])
      end
    end
  end
end
