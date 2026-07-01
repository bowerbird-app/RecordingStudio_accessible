# frozen_string_literal: true

require "test_helper"

class CompatibilityTest < Minitest::Test
  def setup
    reset_addon_loaded_access!
  end

  def teardown
    reset_addon_loaded_access!
  end

  def test_integration_mode_is_core_when_core_access_present
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths, []) do
      assert_equal :core, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_is_addon_when_core_access_missing
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths,
                                                  ["recording_studio_accessible/extracted/recording_studio/access"]) do
      assert_equal :addon, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_stays_addon_after_addon_loads_access_constant
    RecordingStudioAccessible::Compatibility.instance_variable_set(:@addon_loaded_access, true)

    assert_equal :addon, RecordingStudioAccessible::Compatibility.integration_mode
    assert RecordingStudioAccessible::Compatibility.addon_provides_access?
    refute RecordingStudioAccessible::Compatibility.core_access_present?
  end

  def test_missing_constant_paths_load_in_dependency_order
    singleton = RecordingStudioAccessible::Compatibility.singleton_class
    original_method = singleton.instance_method(:constant_defined_path?)
    singleton.send(:define_method, :constant_defined_path?) { |_path| false }

    expected = [
      "recording_studio_accessible/extracted/recording_studio/access"
    ]

    assert_equal expected, RecordingStudioAccessible::Compatibility.missing_constant_paths
  ensure
    singleton.send(:define_method, :constant_defined_path?, original_method)
  end

  def test_ensure_recordable_types_registered
    registered = []

    singleton = RecordingStudioAccessible::Compatibility.singleton_class
    original_method = singleton.instance_method(:constant_defined_path?)
    singleton.send(:define_method, :constant_defined_path?) { |_path| true }

    RecordingStudio.stub(:register_recordable_type, ->(name) { registered << name }) do
      RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    end

    assert_includes registered, "RecordingStudio::Access"
  ensure
    singleton.send(:define_method, :constant_defined_path?, original_method)
  end

  def test_ensure_creation_guards_includes_access_guard_for_core_access
    access_class = Class.new do
      def self.validate(callback, **options)
        validations << [callback, options]
      end

      def self.validations
        @validations ||= []
      end
    end

    recording_class = Class.new do
      def self.validate(callback, **options)
        validations << [callback, options]
      end

      def self.validations
        @validations ||= []
      end
    end

    RecordingStudio.stub(:const_defined?, lambda { |name, inherit = true|
      %w[Access Recording].include?(name.to_s) || Object.const_defined?(name, inherit)
    }) do
      RecordingStudio.stub(:const_get, lambda { |name, inherit = true|
        case name.to_s
        when "Access" then access_class
        when "Recording" then recording_class
        else Object.const_get(name, inherit)
        end
      }) do
        RecordingStudioAccessible::Compatibility.ensure_creation_guards!
      end
    end

    assert_includes access_class.included_modules, RecordingStudioAccessible::AccessCreationGuard
    assert_includes access_class.validations, [:prevent_unsupported_direct_creation, { on: :create }]
    assert_includes recording_class.included_modules, RecordingStudioAccessible::AccessRecordingCreationGuard
    assert_includes recording_class.validations, [:prevent_unsupported_access_recording_creation, { on: :create }]
  end

  def test_ensure_access_recordable_declaration_ignores_class_without_recordable_api
    access_class = Class.new

    RecordingStudio.stub(:const_defined?, lambda { |name, inherit = true|
      name.to_s == "Access" || Object.const_defined?(name, inherit)
    }) do
      RecordingStudio.stub(:const_get, lambda { |name, inherit = true|
        name.to_s == "Access" ? access_class : Object.const_get(name, inherit)
      }) do
        RecordingStudioAccessible::Compatibility.ensure_access_recordable_declaration!
      end
    end
  end

  def test_access_parent_allowed_delegates_to_recording_studio_parent_allowed
    recording = Object.new
    calls = []

    RecordingStudio.stub(:parent_allowed?, lambda { |child_type:, parent_recording:|
      calls << [child_type, parent_recording]
      true
    }) do
      assert RecordingStudioAccessible::Compatibility.access_parent_allowed?(recording)
    end

    assert_equal [[RecordingStudioAccessible::Compatibility::ACCESS_RECORDABLE_TYPE, recording]], calls
  end

  def test_access_parent_allowed_returns_false_when_parent_rejected
    recording = Object.new

    RecordingStudio.stub(:parent_allowed?, false) do
      refute RecordingStudioAccessible::Compatibility.access_parent_allowed?(recording)
    end
  end

  def test_access_parent_allowed_returns_false_when_declarations_are_invalid
    recording = Object.new

    RecordingStudio.stub(:parent_allowed?, ->(**) { raise RecordingStudio::InvalidRecordableDeclaration, "boom" }) do
      refute RecordingStudioAccessible::Compatibility.access_parent_allowed?(recording)
    end
  end

  def test_access_parent_allowed_returns_false_for_blank_recording
    refute RecordingStudioAccessible::Compatibility.access_parent_allowed?(nil)
  end

  def test_register_access_capability_registers_when_no_compatible_core_capability_exists
    registered = []

    RecordingStudio.stub(:registered_capabilities, {}) do
      RecordingStudio.stub(:register_capability, ->(*args, **kwargs) { registered << [args, kwargs] }) do
        RecordingStudioAccessible::Compatibility.register_access_capability!
      end
    end

    assert_equal [[[:accessible], { source: "recording_studio_accessible", child_recordables: ["RecordingStudio::Access"] }]],
                 registered
  end

  def test_register_access_capability_skips_compatible_core_capability
    registered = []
    capabilities = {
      accessible: {
        source: "recording_studio_core",
        child_recordables: ["RecordingStudio::Access"]
      }
    }

    RecordingStudio.stub(:registered_capabilities, capabilities) do
      RecordingStudio.stub(:register_capability, ->(*args, **kwargs) { registered << [args, kwargs] }) do
        RecordingStudioAccessible::Compatibility.register_access_capability!
      end
    end

    assert_empty registered
  end

  def test_warn_if_core_access_present_logs_once_outside_test
    logger = Class.new do
      attr_reader :messages

      def initialize
        @messages = []
      end

      def info(message)
        @messages << message
      end
    end.new
    development_env = ActiveSupport::StringInquirer.new("development")

    RecordingStudioAccessible::Compatibility.stub(:core_access_present?, true) do
      Rails.stub(:env, development_env) do
        Rails.stub(:logger, logger) do
          2.times { RecordingStudioAccessible::Compatibility.warn_if_core_access_present! }
        end
      end
    end

    assert_equal 1, logger.messages.size
    assert_includes logger.messages.first, "RecordingStudio already provides access models"
  ensure
    RecordingStudioAccessible::Compatibility.remove_instance_variable(:@warned_core_access) if
      RecordingStudioAccessible::Compatibility.instance_variable_defined?(:@warned_core_access)
  end

  private

  def reset_addon_loaded_access!
    compatibility = RecordingStudioAccessible::Compatibility
    return unless compatibility.instance_variable_defined?(:@addon_loaded_access)

    compatibility.remove_instance_variable(:@addon_loaded_access)
  end
end
