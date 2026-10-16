# frozen_string_literal: true

require "test_helper"

class AccessRequestGateTest < Minitest::Test
  Request = Struct.new(:host, :port)

  def setup
    @configuration = RecordingStudioAccessible::Configuration.new
    @request = Request.new("localhost", 80)
  end

  def test_register_requires_an_action_and_a_gate
    assert_raises(ArgumentError) { @configuration.register_access_request_gate(nil, Object.new) }
    assert_raises(ArgumentError) { @configuration.register_access_request_gate(:read, nil) }
  end

  def test_blank_action_uses_the_default_gate
    gate = Object.new
    other = Object.new
    @configuration.register_access_request_gate(:default, gate)
    @configuration.register_access_request_gate(:read, other)

    assert_same gate, @configuration.access_request_gate_for(nil)
    assert_same gate, @configuration.access_request_gate_for("")
    assert_same other, @configuration.access_request_gate_for("read")
    assert_same gate, @configuration.access_request_gate_for("skip")
  end

  def test_continuation_keeps_same_host_urls_and_presentation
    modal = { presentation: "modal", access_action: "read" }

    relative = location("/continue?recording_id=1", modal)
    assert_includes relative, "presentation=modal"
    assert_includes relative, "recording_id=1"
    assert_includes relative, "access_action=read"

    absolute = location("http://localhost/continue", modal)
    assert_includes absolute, "http://localhost/continue"
    assert_includes absolute, "presentation=modal"

    assert_nil location("https://evil.example/phish", modal)
    assert_nil location("//evil.example/phish", modal)
    assert_nil location("javascript:alert(1)", modal)
    assert_nil location("http://localhost:3000/continue", modal)
    assert_nil location("", modal)
  end

  def test_metadata_keeps_scalars_and_drops_the_rest
    cleaned = RecordingStudioAccessible::AccessRequestGateMetadata.clean(
      "why" => "Embargo review",
      :confirmed => false,
      "count" => 2,
      "ratio" => 1.5,
      "empty" => nil,
      "Bad-Key" => "nope",
      "note" => "n" * 201,
      "nested" => { "nope" => true },
      "infinite" => Float::INFINITY
    )

    assert_equal(
      { "why" => "Embargo review", "confirmed" => false, "count" => 2, "ratio" => 1.5, "empty" => nil },
      cleaned
    )
  end

  def test_metadata_drops_a_non_hash_and_keys_past_the_limit
    assert_equal({}, RecordingStudioAccessible::AccessRequestGateMetadata.clean("nope"))

    raw = 40.times.to_h { |index| ["key_#{index}", index] }
    cleaned = RecordingStudioAccessible::AccessRequestGateMetadata.clean(raw)

    assert_equal 32, cleaned.size
    assert_equal 0, cleaned["key_0"]
    refute cleaned.key?("key_39")
  end

  def test_metadata_trims_the_document_to_two_kilobytes
    raw = 32.times.to_h { |index| ["key_#{index}", "x" * 200] }
    cleaned = RecordingStudioAccessible::AccessRequestGateMetadata.clean(raw)

    assert_operator ActiveSupport::JSON.encode(cleaned).bytesize, :<=, 2_048
    assert cleaned.key?("key_0")
    refute cleaned.key?("key_31")
  end

  private

  def location(url, carry)
    RecordingStudioAccessible::AccessRequestContinuation.location(url, request: @request, carry: carry)
  end
end
