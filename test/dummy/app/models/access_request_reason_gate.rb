# frozen_string_literal: true

# Example host gate. Only the restricted demo workspace is asked why.
class AccessRequestReasonGate
  NAME = "Restricted Demo Workspace"
  SESSION_KEY = :access_request_reason_gate

  def self.applies?(recording)
    recording&.recordable.try(:name) == NAME
  end

  def self.satisfied?(recording:, actor:, request:)
    return true unless applies?(recording)

    reason_for(recording, actor, request).present?
  end

  def self.continuation_url(recording:, actor:, request:)
    return "/" unless recording && actor && request

    Rails.application.routes.url_helpers.access_request_gate_path(recording_id: recording.id)
  end

  def self.metadata_for(recording:, actor:)
    return {} unless applies?(recording)

    reason = entries(Current.access_request_reason)[entry_key(recording, actor)]
    return {} if reason.blank?

    { "why" => reason }
  end

  def self.metadata_labels
    { "why" => "Why do you want access?" }
  end

  def self.remember(session, recording, actor, reason)
    stored = entries(session[SESSION_KEY])
    stored[entry_key(recording, actor)] = reason.to_s.strip.first(200)
    session[SESSION_KEY] = stored
    Current.access_request_reason = stored
  end

  def self.reason_for(recording, actor, request)
    entries(request&.session&.[](SESSION_KEY))[entry_key(recording, actor)]
  end

  def self.entries(store)
    return {} unless store.is_a?(Hash)

    store.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value.to_s }
  end

  def self.entry_key(recording, actor)
    "#{recording&.id}:#{actor&.id}"
  end
end
