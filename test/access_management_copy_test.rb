# frozen_string_literal: true

require "test_helper"

class AccessManagementCopyTest < Minitest::Test
  RecordingStub = Struct.new(:id)

  def setup
    @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
    RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
    @previous_translations = deep_plain_copy(I18n.backend.translations)
  end

  def teardown
    restore_translations(@previous_translations)
    RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_default_config_uses_gem_copy
    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))

    assert_equal "Manage access", pack.text("manage.title")
    assert_equal "Share access", pack.text("form.new_title")
    assert_equal "Edit access", pack.text("form.edit_title")
    assert_equal "+ Access", pack.text("manage.add")
    assert_equal "Access requests", pack.text("requests.list_title")
    assert_equal "Access", pack.text("manage.access_menu")
  end

  def test_scope_lookup_then_gem_fallback
    store_teams_copy(manage: { title: "Teams", add: "+ Teammate" })
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |recording:, **|
      next unless recording.id == 1

      { scope: "featured_in.teams" }
    end

    teams = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))
    other = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(2))

    assert_equal "Teams", teams.text("manage.title")
    assert_equal "+ Teammate", teams.text("manage.add")
    assert_equal "Share access", teams.text("form.new_title")
    assert_equal "Manage access", other.text("manage.title")
    assert_equal "+ Access", other.text("manage.add")
  end

  def test_explicit_copy_hash_overrides_individual_keys
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |**|
      { "manage.title" => "Teams", "manage.add" => "+ Teammate" }
    end

    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))

    assert_equal "Teams", pack.text("manage.title")
    assert_equal "+ Teammate", pack.text("manage.add")
    assert_equal "Share access", pack.text("form.new_title")
  end

  def test_copy_and_scope_together
    store_teams_copy(manage: { title: "Teams" })
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |**|
      { scope: "featured_in.teams", copy: { "manage.add" => "+ Teammate" } }
    end

    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))

    assert_equal "Teams", pack.text("manage.title")
    assert_equal "+ Teammate", pack.text("manage.add")
  end

  def test_callable_raise_falls_back_to_defaults
    RecordingStudioAccessible.configuration.access_management_copy = ->(**) { raise "boom" }

    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))

    assert_equal "Manage access", pack.text("manage.title")
  end

  def test_junk_return_falls_back_to_defaults
    RecordingStudioAccessible.configuration.access_management_copy = ->(**) { "nope" }

    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(recording: RecordingStub.new(1))

    assert_equal "Manage access", pack.text("manage.title")
  end

  def test_does_not_read_controller_params
    store_teams_copy(manage: { title: "Teams" })
    controller = Object.new
    def controller.params
      { title: "Hacked", copy: { "manage.title" => "From params" } }
    end
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |recording:, **|
      next unless recording.id == 1

      { scope: "featured_in.teams" }
    end

    pack = RecordingStudioAccessible::AccessManagementCopy.resolve(
      recording: RecordingStub.new(1),
      controller: controller
    )

    assert_equal "Teams", pack.text("manage.title")
    refute_equal "Hacked", pack.text("manage.title")
    refute_equal "From params", pack.text("manage.title")
  end

  private

  def store_teams_copy(hash)
    I18n.backend.store_translations(:en, { featured_in: { teams: hash } })
  end

  def restore_translations(snapshot)
    return unless snapshot

    I18n.backend.instance_variable_set(:@translations, snapshot)
    I18n.backend.instance_variable_set(:@initialized, true) if I18n.backend.instance_variable_defined?(:@initialized)
  end

  def deep_plain_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, nested), copy| copy[key] = deep_plain_copy(nested) }
    when Array
      value.map { |nested| deep_plain_copy(nested) }
    else
      value
    end
  end
end
