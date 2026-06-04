# frozen_string_literal: true

require "test_helper"

class CompatibilityTest < Minitest::Test
  def teardown
    RecordingStudioAccessible::Compatibility.remove_instance_variable(:@addon_loaded_access) if
      RecordingStudioAccessible::Compatibility.instance_variable_defined?(:@addon_loaded_access)
  end

  def test_integration_mode_is_core_when_core_access_present
    stub_singleton(RecordingStudioAccessible::Compatibility, :missing_constant_paths, -> { [] }) do
      assert_equal :core, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_is_addon_when_core_access_missing
    stub_singleton(
      RecordingStudioAccessible::Compatibility,
      :missing_constant_paths,
      -> { ["recording_studio_accessible/extracted/recording_studio/access"] }
    ) do
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
    capabilities = []

    singleton = RecordingStudioAccessible::Compatibility.singleton_class
    original_method = singleton.instance_method(:constant_defined_path?)
    singleton.send(:define_method, :constant_defined_path?) { |_path| true }

    stub_recording_studio(:register_recordable_type, ->(name) { registered << name }) do
      stub_recording_studio(:register_capability, ->(name, **options) { capabilities << [name, options] }) do
        RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
      end
    end

    assert_includes registered, "RecordingStudio::Access"
    assert_includes capabilities,
                    [
                      :accessible,
                      {
                        source: "recording_studio_accessible",
                        child_recordables: ["RecordingStudio::Access"]
                      }
                    ]
  ensure
    singleton.send(:define_method, :constant_defined_path?, original_method)
  end

  def test_enable_access_capability_registers_and_enables_core_capability
    capabilities = []

    stub_recording_studio(:register_capability, ->(name, **options) { capabilities << [name, options] }) do
      stub_recording_studio(:enable_capability, ->(name, on:) { capabilities << [name, { on: on }] }) do
        RecordingStudioAccessible::Compatibility.enable_access_capability!("Workspace")
      end
    end

    assert_equal [
      [
        :accessible,
        {
          source: "recording_studio_accessible",
          child_recordables: ["RecordingStudio::Access"]
        }
      ],
      [:accessible, { on: "Workspace" }]
    ], capabilities
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

    stub_recording_studio(:const_defined?, lambda { |name, inherit = true|
      %w[Access Recording].include?(name.to_s) || Object.const_defined?(name, inherit)
    }) do
      stub_recording_studio(:const_get, lambda { |name, inherit = true|
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

    stub_recording_studio(:const_defined?, lambda { |name, inherit = true|
      name.to_s == "Access" || Object.const_defined?(name, inherit)
    }) do
      stub_recording_studio(:const_get, lambda { |name, inherit = true|
        name.to_s == "Access" ? access_class : Object.const_get(name, inherit)
      }) do
        RecordingStudioAccessible::Compatibility.ensure_access_recordable_declaration!
      end
    end
  end

  def test_ensure_access_recordable_declaration_keeps_access_child_only_without_parent_types
    declarations = []
    access_class = Class.new do
      define_singleton_method(:recording_studio_recordable) do |**options|
        declarations << options
      end
    end

    stub_recording_studio(:const_defined?, lambda { |name, inherit = true|
      name.to_s == "Access" || Object.const_defined?(name, inherit)
    }) do
      stub_recording_studio(:const_get, lambda { |name, inherit = true|
        name.to_s == "Access" ? access_class : Object.const_get(name, inherit)
      }) do
        RecordingStudioAccessible::Compatibility.ensure_access_recordable_declaration!
      end
    end

    assert_equal [{ label: "Access", root: false }], declarations
  end

  private

  def stub_recording_studio(method_name, implementation, &)
    stub_singleton(RecordingStudio, method_name, implementation, &)
  end

  def stub_singleton(object, method_name, implementation)
    singleton = object.singleton_class
    original_method = singleton.instance_method(method_name)
    singleton.send(:define_method, method_name, implementation)

    yield
  ensure
    singleton.send(:define_method, method_name, original_method)
  end
end
