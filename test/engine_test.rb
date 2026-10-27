# frozen_string_literal: true

require "test_helper"
require "active_record"
require "fileutils"
require "tmpdir"
require "pathname"
require "yaml"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
    RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
  end

  def teardown
    RecordingStudioAccessible.configuration.hooks.clear!
    RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    RecordingStudioAccessible.configuration.hooks.before_initialize { before_called = true }
    RecordingStudioAccessible.configuration.hooks.after_initialize { after_called = true }

    find_initializer("recording_studio_accessible.before_initialize").block.call
    find_initializer("recording_studio_accessible.after_initialize").block.call

    assert before_called
    assert after_called
  end

  def test_load_config_leaves_defaults_when_yaml_file_is_missing
    Dir.mktmpdir do |dir|
      app = config_app(root: Pathname(dir), yaml: { warn_on_core_conflict: false })

      find_initializer("recording_studio_accessible.load_config").block.call(app)

      assert RecordingStudioAccessible.configuration.warn_on_core_conflict
    end
  end

  def test_load_config_raises_when_yaml_is_malformed
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "recording_studio_accessible.yml"), ":\n  - :\n")
      app = config_app(root: Pathname(dir))

      assert_raises(Psych::SyntaxError) do
        find_initializer("recording_studio_accessible.load_config").block.call(app)
      end
    end
  end

  def test_load_config_merges_yaml_when_file_exists
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(
        File.join(dir, "config", "recording_studio_accessible.yml"),
        { "warn_on_core_conflict" => false }.to_yaml
      )
      app = config_app(root: Pathname(dir))

      find_initializer("recording_studio_accessible.load_config").block.call(app)

      assert_equal false, RecordingStudioAccessible.configuration.warn_on_core_conflict
    end
  end

  def test_load_config_merges_yaml_and_config_x
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(
        File.join(dir, "config", "recording_studio_accessible.yml"),
        { "warn_on_core_conflict" => true }.to_yaml
      )
      xcfg = Struct.new(:recording_studio_accessible).new({ warn_on_core_conflict: false })
      app = config_app(root: Pathname(dir), xcfg: xcfg)

      find_initializer("recording_studio_accessible.load_config").block.call(app)

      assert_equal false, RecordingStudioAccessible.configuration.warn_on_core_conflict
    end
  end

  def test_register_access_types_initializer_calls_compatibility_helpers
    events = []
    warn = -> { events << :warned }
    register = -> { events << :registered }
    guard = -> { events << :guarded }

    RecordingStudioAccessible::Compatibility.stub(:warn_if_core_access_present!, warn) do
      RecordingStudioAccessible::Compatibility.stub(:ensure_recordable_types_registered!, register) do
        RecordingStudioAccessible::Compatibility.stub(:ensure_creation_guards!, guard) do
          find_initializer("recording_studio_accessible.register_access_types").block.call
        end
      end
    end

    assert_equal %i[warned registered guarded], events
  end

  def test_load_missing_constants_initializer_loads_extracted_models_against_top_level_application_record
    return if RecordingStudio.const_defined?(:Access, false)

    application_record = Class.new(::ActiveRecord::Base) do
      self.abstract_class = true
    end

    Object.const_set(:ApplicationRecord, application_record)

    find_initializer("recording_studio_accessible.load_missing_constants").block.call

    assert_equal application_record, RecordingStudio::Access.superclass
  ensure
    RecordingStudio.send(:remove_const, :Access) if RecordingStudio.const_defined?(:Access, false)
    Object.send(:remove_const, :ApplicationRecord) if Object.const_defined?(:ApplicationRecord,
                                                                            false) && Object.const_get(:ApplicationRecord) == application_record
  end

  def test_register_shipped_english_initializer_is_ordered_before_recording_studio_load
    initializer = find_initializer("recording_studio_accessible.register_shipped_english")
    refute_nil initializer
    assert_equal "recording_studio.load_shipped_english", initializer.before
  end

  private

  def find_initializer(name)
    RecordingStudioAccessible::Engine.initializers.find { |initializer| initializer.name == name }
  end

  def config_app(root:, yaml: nil, xcfg: nil)
    app_config = Struct.new(:x).new(xcfg)
    Class.new do
      def initialize(root, config, yaml)
        @root = root
        @config = config
        @yaml = yaml
      end

      attr_reader :root, :config

      def config_for(_name)
        path = root.join("config", "recording_studio_accessible.yml")
        loaded = YAML.safe_load_file(path)
        return loaded if loaded.respond_to?(:each)

        @yaml
      end
    end.new(root, app_config, yaml)
  end
end
