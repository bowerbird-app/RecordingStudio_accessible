# frozen_string_literal: true

require "test_helper"

class AuthorizationClassMethodsTest < Minitest::Test
  Subject = Class.new do
    extend RecordingStudioAccessible::AuthorizationClassMethods

    class << self
      attr_accessor :call_value
      attr_reader :calls

      def reset!
        @calls = []
        @call_value = nil
      end

      def call(**kwargs)
        @calls << kwargs
        RecordingStudioAccessible::Services::BaseService::Result.new(success: true, value: @call_value)
      end
    end
  end

  Actor = Struct.new(:id) do
    def self.base_class
      self
    end
  end

  def setup
    Subject.reset!
    @configuration = RecordingStudioAccessible.configuration
    ensure_access_class!
    ensure_recording_class!
  end

  def teardown
    RecordingStudio.send(:remove_const, :Access) if @created_access_class
    RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
  end

  def test_role_for_returns_nil_without_actor
    assert_nil Subject.role_for(actor: nil, recording: :recording)
    assert_empty Subject.calls
  end

  def test_role_for_delegates_to_service_call
    Subject.call_value = :admin

    assert_equal :admin, Subject.role_for(actor: :actor, recording: :recording)
    assert_equal [{ actor: :actor, recording: :recording }], Subject.calls
  end

  def test_allowed_fails_closed_for_missing_inputs_and_invalid_roles
    refute Subject.allowed?(actor: nil, recording: :recording, role: :view)
    refute Subject.allowed?(actor: :actor, recording: nil, role: :view)
    refute Subject.allowed?(actor: :actor, recording: :recording, role: :missing)
    assert_empty Subject.calls
  end

  def test_allowed_delegates_to_service_call_for_valid_roles
    Subject.call_value = true

    assert Subject.allowed?(actor: :actor, recording: :recording, role: :edit)
    assert_equal [{ actor: :actor, recording: :recording, role: :edit }], Subject.calls
  end

  def test_allowed_through_requires_configuration_authorization
    Subject.call_value = true
    @configuration.stub(:authorize_actor_through?, false) do
      refute Subject.allowed_through?(actor: :actor, through: :through, recording: :recording, role: :view)
    end

    assert_empty Subject.calls
  end

  def test_allowed_through_authorizes_through_actor_role
    Subject.call_value = true
    captured = nil
    authorizer = lambda do |**kwargs|
      captured = kwargs
      true
    end

    @configuration.stub(:authorize_actor_through?, authorizer) do
      assert Subject.allowed_through?(actor: :actor, through: :through, recording: :recording, role: :view,
                                      controller: :controller)
    end

    assert_equal({ actor: :actor, through: :through, recording: :recording, role: :view, controller: :controller },
                 captured)
    assert_equal [{ actor: :through, recording: :recording, role: :view }], Subject.calls
  end

  def test_role_through_returns_nil_when_authorization_fails
    @configuration.stub(:authorize_actor_through?, false) do
      assert_nil Subject.role_through(actor: :actor, through: :through, recording: :recording)
    end

    assert_empty Subject.calls
  end

  def test_role_through_returns_authorized_through_actor_role
    Subject.call_value = :edit

    @configuration.stub(:authorize_actor_through?, true) do
      assert_equal :edit, Subject.role_through(actor: :actor, through: :through, recording: :recording)
    end

    assert_equal [{ actor: :through, recording: :recording }], Subject.calls
  end

  def test_root_collection_methods_return_empty_without_actor
    assert_equal [], Subject.root_recordings_for(actor: nil)
    assert_equal [], Subject.root_recording_ids_for(actor: nil)
  end

  def test_root_recording_ids_for_filters_access_scope_by_minimum_role
    actor = Actor.new(42)
    access_scope = Relation.new
    root_access_scope = Relation.new(pluck_values: [10, 20])

    RecordingStudio::Access.stub(:where, access_scope) do
      RecordingStudio::Recording.stub(:unscoped, root_access_scope) do
        RecordingStudio::Recording.stub(:column_names, []) do
          assert_equal [10, 20], Subject.root_recording_ids_for(actor: actor, minimum_role: :edit)
        end
      end
    end

    assert(access_scope.wheres.any? { |where| where.key?(:role) })
    assert_includes root_access_scope.wheres, { recordable_type: "RecordingStudio::Access" }
    assert_includes root_access_scope.not_wheres, { root_recording_id: nil }
  end

  def test_root_recordings_for_returns_distinct_roots_when_access_exists
    actor = Actor.new(42)
    access_scope = Relation.new
    root_access_scope = Relation.new(exists_value: true, to_a_values: [:root_recording])

    RecordingStudio::Access.stub(:where, access_scope) do
      RecordingStudio::Recording.stub(:unscoped, root_access_scope) do
        RecordingStudio::Recording.stub(:column_names, []) do
          assert_equal [:root_recording], Subject.root_recordings_for(actor: actor)
        end
      end
    end
  end

  def test_access_recording_helpers_delegate_to_direct_access_query
    access_recordings = [:access_recording]

    RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_for, access_recordings) do
      assert_equal access_recordings, Subject.access_recordings_for(:recording)
    end

    RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_for_actor, access_recordings) do
      assert_equal access_recordings, Subject.access_recordings_for_actor(recording: :recording, actor: :actor)
    end
  end

  private

  def ensure_access_class!
    return if RecordingStudio.const_defined?(:Access, false)

    @created_access_class = true
    RecordingStudio.const_set(:Access, Class.new do
      def self.roles
        { "view" => 0, "edit" => 1, "admin" => 2 }
      end

      def self.where(*) = nil
    end)
  end

  def ensure_recording_class!
    return if RecordingStudio.const_defined?(:Recording, false)

    @created_recording_class = true
    RecordingStudio.const_set(:Recording, Class.new do
      def self.unscoped = nil
      def self.column_names = []
      def self.none = []
    end)
  end

  class Relation
    attr_reader :wheres, :not_wheres

    def initialize(pluck_values: [], to_a_values: [], exists_value: true)
      @pluck_values = pluck_values
      @to_a_values = to_a_values
      @exists_value = exists_value
      @wheres = []
      @not_wheres = []
    end

    def where(*args)
      @wheres << args.first
      self
    end

    def not(*args)
      @not_wheres << args.first
      self
    end

    def select(*) = self
    def distinct = self
    def exists? = @exists_value
    def pluck(*) = @pluck_values
    def to_a = @to_a_values
  end
end
