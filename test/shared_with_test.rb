# frozen_string_literal: true

require "test_helper"

class SharedWithTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAccessible.configuration
    @resolver = @configuration.shared_item_resolver
    @configuration.shared_item_resolver = nil
  end

  def teardown
    @configuration.shared_item_resolver = @resolver
  end

  def test_a_nil_actor_returns_an_empty_page
    page = RecordingStudioAccessible.shared_with(actor: nil)

    assert_empty page.items
    assert_nil page.next_cursor
    refute page.has_more
  end

  def test_an_unset_resolver_returns_an_empty_page
    page = RecordingStudioAccessible.shared_with(actor: supported_actor)

    assert_empty page.items
    refute page.has_more
  end

  def test_an_unsupported_actor_type_is_rejected
    assert_raises(ArgumentError) { RecordingStudioAccessible.shared_with(actor: Object.new) }
    assert_raises(ArgumentError) { RecordingStudioAccessible.shared_with(actor: "person") }
  end

  def test_an_invalid_cursor_is_rejected
    error = assert_raises(RecordingStudioAccessible::SharedWith::InvalidCursor) do
      RecordingStudioAccessible.shared_with(actor: supported_actor, cursor: "not-a-cursor")
    end

    assert_kind_of ArgumentError, error
  end

  private

  def supported_actor
    actor_class.new
  end

  def actor_class
    Class.new do
      def self.base_class
        self
      end

      def self.polymorphic_name
        "User"
      end

      def id
        "00000000-0000-0000-0000-000000000001"
      end
    end
  end
end
