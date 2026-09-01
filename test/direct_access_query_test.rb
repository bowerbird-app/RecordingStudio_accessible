# frozen_string_literal: true

require "test_helper"

class DirectAccessQueryTest < Minitest::Test
  Recording = Struct.new(:id)
  Actor = Struct.new(:id) do
    def self.base_class
      self
    end
  end

  class RelationSpy
    attr_reader :wheres, :joins_sql, :orders

    def initialize
      @wheres = []
      @joins_sql = []
      @orders = []
    end

    def where(*args)
      @wheres << args
      self
    end

    def joins(sql)
      @joins_sql << sql
      self
    end

    def order(ordering)
      @orders << ordering
      self
    end
  end

  def setup
    ensure_recording_class!
  end

  def teardown
    RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
  end

  def test_access_recordings_for_filters_to_active_access_children
    relation = RelationSpy.new

    RecordingStudio::Recording.stub(:unscoped, relation) do
      RecordingStudio::Recording.stub(:column_names, ["trashed_at"]) do
        assert_same relation, RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(Recording.new(123))
      end
    end

    assert_includes relation.wheres, [{ trashed_at: nil }]
    assert_includes relation.wheres, [{ parent_recording_id: 123 }]
    assert_includes relation.wheres, [{ recordable_type: "RecordingStudio::Access" }]
  end

  def test_access_recordings_for_actor_returns_none_without_actor
    none_scope = Object.new

    RecordingStudio::Recording.stub(:none, none_scope) do
      assert_same none_scope,
                  RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: :recording,
                                                                                           actor: nil)
    end
  end

  def test_access_recordings_for_actor_joins_access_rows_and_orders_newest_first
    relation = RelationSpy.new
    actor = Actor.new(456)

    RecordingStudio::Recording.stub(:unscoped, relation) do
      RecordingStudio::Recording.stub(:column_names, []) do
        assert_same relation,
                    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: Recording.new(123),
                                                                                             actor: actor)
      end
    end

    assert_equal [RecordingStudioAccessible::DirectAccessQuery::ACCESS_JOIN_SQL], relation.joins_sql
    assert_includes relation.wheres, [{ recording_studio_accesses: { actor_type: "DirectAccessQueryTest::Actor", actor_id: 456 } }]
    assert_equal [{ created_at: :desc, id: :desc }], relation.orders
  end

  def test_access_recordings_for_actor_in_returns_none_without_recording_ids
    none_scope = Object.new

    RecordingStudio::Recording.stub(:none, none_scope) do
      assert_same none_scope,
                  RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor_in(recordings: [Recording.new(nil)],
                                                                                              actor: Actor.new(1))
    end
  end

  def test_access_recordings_for_actor_in_filters_parent_ids
    relation = RelationSpy.new
    actor = Actor.new(456)

    RecordingStudio::Recording.stub(:unscoped, relation) do
      RecordingStudio::Recording.stub(:column_names, []) do
        assert_same relation,
                    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor_in(recordings: [Recording.new(1), Recording.new(2)],
                                                                                                actor: actor)
      end
    end

    assert_includes relation.wheres, [{ parent_recording_id: [1, 2], recordable_type: "RecordingStudio::Access" }]
    assert_includes relation.wheres, [{ recording_studio_accesses: { actor_type: "DirectAccessQueryTest::Actor", actor_id: 456 } }]
  end

  def test_access_recordings_depending_on_returns_none_without_recording_id
    none_scope = Object.new

    RecordingStudio::Recording.stub(:none, none_scope) do
      assert_same none_scope, RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on(nil)
    end
  end

  def test_access_recordings_depending_on_returns_none_when_the_column_is_unavailable
    none_scope = Object.new

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, false) do
      RecordingStudio::Recording.stub(:none, none_scope) do
        assert_same none_scope, RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on("manager-id")
      end
    end
  end

  def test_access_recordings_depending_on_filters_by_manager_recording_id
    relation = RelationSpy.new

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudio::Recording.stub(:unscoped, relation) do
        RecordingStudio::Recording.stub(:column_names, []) do
          assert_same relation, RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on("manager-id")
        end
      end
    end

    assert_includes relation.wheres, [{ recordable_type: "RecordingStudio::Access" }]
    assert_includes relation.wheres, [{ recording_studio_accesses: { depends_on_recording_id: "manager-id" } }]
  end

  private

  def ensure_recording_class!
    return if RecordingStudio.const_defined?(:Recording, false)

    @created_recording_class = true
    RecordingStudio.const_set(:Recording, Class.new do
      def self.unscoped = nil
      def self.none = nil
      def self.column_names = []
    end)
  end
end
