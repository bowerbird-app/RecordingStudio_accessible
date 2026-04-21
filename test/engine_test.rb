# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = GemTemplate.instance_variable_get(:@configuration)
    GemTemplate.instance_variable_set(:@configuration, GemTemplate::Configuration.new)
  end

  def teardown
    GemTemplate.configuration.hooks.clear!
    GemTemplate.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    GemTemplate.configuration.hooks.before_initialize { |_engine| before_called = true }
    GemTemplate.configuration.hooks.after_initialize { |_engine| after_called = true }

    find_initializer("gem_template.before_initialize").block.call(Object.new)
    find_initializer("gem_template.after_initialize").block.call(Object.new)

    assert before_called
    assert after_called
  end

  def test_load_config_merges_config_sources_and_runs_on_configuration_hook
    hook_called = false
    hook_payload = nil
    GemTemplate.configuration.hooks.on_configuration do |cfg|
      hook_called = true
      hook_payload = cfg
    end

    xcfg = Struct.new(:gem_template).new({ enable_feature_x: true })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { api_key: "from_yaml", timeout: 12 }
      end
    end.new(app_config)

    find_initializer("gem_template.load_config").block.call(app)

    assert hook_called
    assert_equal GemTemplate.configuration, hook_payload
    assert_equal "from_yaml", GemTemplate.configuration.api_key
    assert_equal 12, GemTemplate.configuration.timeout
    assert_equal true, GemTemplate.configuration.enable_feature_x
  end

  def test_load_config_handles_errors_and_each_pair_fallback
    pair_config = Class.new do
      def each_pair
        yield(:timeout, 15)
      end
    end.new

    xcfg = Struct.new(:gem_template).new(pair_config)
    app_config = Struct.new(:x).new(xcfg)

    app = Struct.new(:config) do
      def config_for(_name)
        raise "missing file"
      end
    end.new(app_config)

    find_initializer("gem_template.load_config").block.call(app)

    assert_equal 15, GemTemplate.configuration.timeout
  end

  def test_load_config_swallow_each_pair_errors
    bad_pair_config = Class.new do
      def each_pair
        raise "bad pair"
      end
    end.new

    xcfg = Struct.new(:gem_template).new(bad_pair_config)
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { api_key: "ok" }
      end
    end.new(app_config)

    # Should not raise even if xcfg.each_pair fails.
    find_initializer("gem_template.load_config").block.call(app)

    assert_equal "ok", GemTemplate.configuration.api_key
  end

  def test_apply_extension_initializers_register_active_support_on_load_callbacks
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    GemTemplate::Engine.stub(:config, config_stub) do
      find_initializer("gem_template.apply_model_extensions").block.call
      find_initializer("gem_template.apply_controller_extensions").block.call
    end

    assert_equal 2, to_prepare_blocks.size
  end

  def test_apply_model_extensions_adds_registered_methods_once
    model_class = Class.new do
      def self.name
        "ExampleRecord"
      end
    end

    GemTemplate.configuration.hooks.extend_model(:ExampleRecord) do
      def template_extension_method
        :applied
      end
    end

    GemTemplate::Engine.apply_model_extensions(model_class)
    GemTemplate::Engine.apply_model_extensions(model_class)

    instance = model_class.new
    assert_equal :applied, instance.template_extension_method
  end

  def test_apply_controller_extensions_matches_demodulized_name
    controller_class = Class.new do
      def self.name
        "Admin::DashboardController"
      end
    end

    GemTemplate.configuration.hooks.extend_controller(:DashboardController) do
      def template_controller_extension
        :applied
      end
    end

    GemTemplate::Engine.apply_controller_extensions(controller_class)

    instance = controller_class.new
    assert_equal :applied, instance.template_controller_extension
  end

  private

  def find_initializer(name)
    GemTemplate::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
