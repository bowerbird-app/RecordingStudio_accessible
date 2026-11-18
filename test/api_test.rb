# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/api"

class ApiTest < Minitest::Test
  def test_registration_is_a_noop_without_recording_studio_api
    refute Object.const_defined?(:RecordingStudioApi, false)

    assert_nil RecordingStudioAccessible::Api.register_capability_actions!
  end

  def test_registration_registers_accessible_member_actions
    with_fake_recording_studio_api do |api|
      RecordingStudioAccessible::Api.register_capability_actions!

      names = api.registrations.map { |registration| registration.fetch(:name) }
      assert_equal %i[list_access grant_access update_access revoke_access], names

      api.registrations.each do |registration|
        assert_equal :accessible, registration.fetch(:capability)
        assert_equal :admin, registration.fetch(:required_role)
        assert_equal :member, registration.fetch(:scope)
        assert_equal :post, registration.fetch(:http_verb)
        assert_equal "1.0.0", registration.fetch(:version)
        assert registration.fetch(:handler).respond_to?(:call)
      end
    end
  end

  def test_registration_does_not_reregister_existing_actions
    with_fake_recording_studio_api(existing_actions: { public: :list_access }) do |api|
      RecordingStudioAccessible::Api.register_capability_actions!

      names = api.registrations.map { |registration| registration.fetch(:name) }
      refute_includes names, :list_access
      assert_includes names, :grant_access
    end
  end

  def test_registration_warns_when_existing_required_role_differs
    existing = Struct.new(:name, :required_role).new(:list_access, :view)

    with_fake_recording_studio_api(existing_actions: { public: existing }) do |api|
      _out, err = capture_io do
        RecordingStudioAccessible::Api.register_capability_actions!
      end

      names = api.registrations.map { |registration| registration.fetch(:name) }
      refute_includes names, :list_access
      assert_match(/list_access.*required_role=:view.*:admin/, err)
    end
  end

  def test_registration_covers_each_named_api
    with_fake_recording_studio_api(api_names: %i[public operations]) do |api|
      RecordingStudioAccessible::Api.register_capability_actions!

      by_api = api.registrations.group_by { |registration| registration.fetch(:api) }
      assert_equal %w[public operations], by_api.keys
      by_api.each_value do |registrations|
        assert_equal 4, registrations.size
      end
    end
  end

  def test_grant_and_update_access_role_fields_describe_defaults_without_enum
    expected = "Default roles: #{RecordingStudioAccessible::RoleSet::DEFAULT_NAMES.join(', ')}. " \
               "Types may declare others."

    %i[grant_access update_access].each do |action|
      role_field = RecordingStudioAccessible::Api::ACTION_DEFINITIONS
                   .fetch(action)
                   .fetch(:fields)
                   .fetch(:role)

      assert_includes role_field.fetch(:description), expected
      refute role_field.key?(:enum)
    end
  end

  def test_access_actions_document_real_200_schemas
    grant = schema_for(:grant_access)
    list = schema_for(:list_access)
    revoke = schema_for(:revoke_access)
    update = schema_for(:update_access)

    assert_includes schema_property_names(grant), "invited"
    assert_includes schema_property_names(grant), "email"
    assert_includes schema_property_names(grant), "actor"
    assert_includes schema_property_names(grant), "source_recording"
    assert_includes schema_property_names(grant), "notice"

    assert_includes schema_property_names(list), "grants"
    assert_includes schema_property_names(list), "email"
    assert_includes schema_property_names(list), "status"
    assert_includes schema_property_names(list), "actor"

    assert_includes schema_property_names(revoke), "revoked"
    assert_includes schema_property_names(revoke), "actor"
    assert_includes schema_property_names(revoke), "id"
    assert_includes schema_property_names(revoke), "label"

    assert_includes schema_property_names(update), "invited"
    assert_includes schema_property_names(update), "inherited"
    assert_includes schema_property_names(update), "role"
    assert_includes schema_property_names(update), "effective_role"
    assert_includes schema_property_names(update), "actor"
    assert_includes schema_property_names(update), "source_recording"
    refute_includes schema_property_names(update), "notice"
  end

  def test_generic_access_descriptions_are_the_approved_defaults
    copy = RecordingStudioAccessible::Api::OpenapiCopy

    assert_equal copy::GRANT_ACCESS_SUMMARY, openapi_for(:grant_access).fetch(:summary)
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION,
                 openapi_for(:grant_access).fetch(:description)
    assert_equal copy::LIST_ACCESS_SUMMARY, openapi_for(:list_access).fetch(:summary)
    assert_equal RecordingStudioAccessible::Api::LIST_ACCESS_DESCRIPTION,
                 openapi_for(:list_access).fetch(:description)
    assert_equal copy::REVOKE_ACCESS_SUMMARY, openapi_for(:revoke_access).fetch(:summary)
    assert_equal RecordingStudioAccessible::Api::REVOKE_ACCESS_DESCRIPTION,
                 openapi_for(:revoke_access).fetch(:description)
    assert_equal copy::UPDATE_ACCESS_SUMMARY, openapi_for(:update_access).fetch(:summary)
    assert_equal RecordingStudioAccessible::Api::UPDATE_ACCESS_DESCRIPTION,
                 openapi_for(:update_access).fetch(:description)
  end

  def test_access_action_copy_omits_caller_permission_wording
    RecordingStudioAccessible::Api::ACTION_NAMES.each do |name|
      definition = RecordingStudioAccessible::Api::ACTION_DEFINITIONS.fetch(name)
      blob = [
        definition.fetch(:openapi).fetch(:summary),
        definition.fetch(:openapi).fetch(:description),
        definition.fetch(:fields).values.filter_map { |field| field[:description] }
      ].flatten.join(" ")

      refute_match(/requires .* role/i, blob)
      refute_match(/\badmin only\b/i, blob)
      refute_includes blob, ":edit"
      refute_includes blob, "Access:"
      refute_includes blob, "You cannot grant a role higher"
      refute_includes blob, "unless you are an admin"
      refute_includes blob, "Press Kit"
      refute_includes blob, "Press Center"
    end
  end

  def test_openapi_override_is_per_type
    RecordingStudioAccessible::Api.override_openapi(
      type: "Folder",
      action: :grant_access,
      title: "Folder - Grant Access",
      description: "Folder-only grant copy."
    )

    folder = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "Folder")
    workspace = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "Workspace")
    generic = RecordingStudioAccessible::Api.openapi_for(:grant_access)

    assert_equal "Folder - Grant Access", folder.fetch(:title)
    assert_equal "Folder-only grant copy.", folder.fetch(:description)
    refute folder.key?(:tag_suffix)
    refute folder.equal?(RecordingStudioAccessible::Api::ACTION_DEFINITIONS.fetch(:grant_access).fetch(:openapi))
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, workspace.fetch(:description)
    refute workspace.key?(:title)
    refute workspace.key?(:tag_suffix)
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, generic.fetch(:description)
    refute generic.key?(:title)
    refute generic.key?(:tag_suffix)
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_registration_keeps_generic_openapi_when_a_type_is_overridden
    RecordingStudioAccessible::Api.override_openapi(
      type: "Folder",
      action: :grant_access,
      title: "Folder - Grant Access",
      description: "Folder-only grant copy."
    )

    with_fake_recording_studio_api do |api|
      RecordingStudioAccessible::Api.register_capability_actions!
      grant = api.registrations.find { |registration| registration.fetch(:name) == :grant_access }

      assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION,
                   grant.fetch(:openapi).fetch(:description)
      refute grant.fetch(:openapi).key?(:title)
      refute grant.fetch(:openapi).key?(:tag_suffix)
    end
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_tag_suffix_is_returned_for_that_type_only
    RecordingStudioAccessible::Api.override_openapi(
      type: "PressCenter",
      action: :grant_access,
      tag_suffix: "Access",
      description: "Grant a role on this press center."
    )

    press_center = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "PressCenter")
    folder = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "Folder")
    generic = RecordingStudioAccessible::Api.openapi_for(:grant_access)
    listed = RecordingStudioAccessible::Api.openapi_for(:list_access, type: "PressCenter")

    assert_equal "Access", press_center.fetch(:tag_suffix)
    assert_equal "Grant a role on this press center.", press_center.fetch(:description)
    refute press_center.key?(:title)
    assert_equal RecordingStudioAccessible::Api::OpenapiCopy::GRANT_ACCESS_SUMMARY, press_center.fetch(:summary)
    refute folder.key?(:tag_suffix)
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, folder.fetch(:description)
    refute generic.key?(:tag_suffix)
    refute listed.key?(:tag_suffix)
    assert_equal RecordingStudioAccessible::Api::LIST_ACCESS_DESCRIPTION, listed.fetch(:description)
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_tag_suffix_alone_keeps_the_generic_title_and_description
    RecordingStudioAccessible::Api.override_openapi(
      type: "PressCenter",
      action: :grant_access,
      tag_suffix: "Access"
    )

    press_center = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "PressCenter")

    assert_equal "Access", press_center.fetch(:tag_suffix)
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, press_center.fetch(:description)
    refute press_center.key?(:title)
    refute RecordingStudioAccessible::Api.openapi_for(:grant_access).key?(:tag_suffix)
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_registered_openapi_for_returns_tag_suffix_for_that_type
    RecordingStudioAccessible::Api.override_openapi(
      type: "PressCenter",
      action: :grant_access,
      tag_suffix: "Access"
    )

    with_fake_recording_studio_api do |api|
      RecordingStudioAccessible::Api.register_capability_actions!
      grant = api.registrations.find { |registration| registration.fetch(:name) == :grant_access }
      lookup = grant.fetch(:openapi_for)

      press_center = lookup.call(type: "PressCenter", action: :grant_access)
      workspace = lookup.call(type: "Workspace", action: :grant_access)

      assert_equal "Access", press_center.fetch(:tag_suffix)
      assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, press_center.fetch(:description)
      refute press_center.key?(:title)
      refute workspace.key?(:tag_suffix)
      refute grant.fetch(:openapi).key?(:tag_suffix)
    end
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_openapi_override_accepts_a_title_without_a_description
    RecordingStudioAccessible::Api.override_openapi(
      type: "Folder",
      action: :update_access,
      title: "Folder - Update Access"
    )

    folder = RecordingStudioAccessible::Api.openapi_for(:update_access, type: "Folder")

    assert_equal "Folder - Update Access", folder.fetch(:title)
    assert_equal RecordingStudioAccessible::Api::UPDATE_ACCESS_DESCRIPTION, folder.fetch(:description)
    refute folder.key?(:tag_suffix)
    refute RecordingStudioAccessible::Api.openapi_for(:update_access).key?(:title)
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  def test_openapi_override_rejects_a_call_with_no_fields
    assert_raises(ArgumentError) do
      RecordingStudioAccessible::Api.override_openapi(type: "PressCenter", action: :grant_access)
    end
  end

  def test_openapi_override_rejects_unknown_action_and_missing_type
    assert_raises(ArgumentError) do
      RecordingStudioAccessible::Api.override_openapi(
        type: "PressCenter",
        action: :not_an_action,
        tag_suffix: "Access"
      )
    end

    assert_raises(ArgumentError) do
      RecordingStudioAccessible::Api.override_openapi(type: nil, action: :grant_access, tag_suffix: "Access")
    end

    assert_raises(ArgumentError) do
      RecordingStudioAccessible::Api.override_openapi(type: "", action: :grant_access, tag_suffix: "Access")
    end
  end

  def test_openapi_override_still_rejects_a_nil_description
    assert_raises(ArgumentError) do
      RecordingStudioAccessible::Api.override_openapi(
        type: "Folder",
        action: :grant_access,
        title: "Folder - Grant Access",
        description: nil
      )
    end
  end

  def test_list_access_contract_rejects_unknown_keys_after_filtering_route_params
    with_fake_recording_studio_api do |api|
      RecordingStudioAccessible::Api.register_capability_actions!
      contract = api.registrations.first.fetch(:input_contract)

      result = contract.call(api_key: "public", api_version: "v1", member_action: "list_access", surprise: "no")

      refute result.success?
      assert_includes result.errors.join, "surprise"
    end
  end

  private

  def with_fake_recording_studio_api(existing_actions: {}, api_names: nil)
    api = Module.new
    invalid_action_input_error = Class.new(StandardError) do
      attr_reader :details

      def initialize(message, details: [])
        super(message)
        @details = details
      end
    end

    api.const_set(:InvalidActionInputError, invalid_action_input_error)
    api.const_set(:AuthorizationError, Class.new(StandardError))
    api.const_set(:NotFoundError, Class.new(StandardError))
    api.const_set(:ActionInputContract, fake_action_input_contract_class)
    api.instance_variable_set(:@existing_actions, existing_actions.transform_keys(&:to_s))
    api.instance_variable_set(:@registrations, [])

    if api_names
      define_named_api_behavior(api, api_names)
    else
      api.define_singleton_method(:capability_action) do |name|
        matching_existing_action(@existing_actions["public"], name)
      end
      api.define_singleton_method(:register_capability_action) do |name, **options|
        @registrations << options.merge(name: name)
      end
    end

    api.define_singleton_method(:registrations) { @registrations }

    api.define_singleton_method(:matching_existing_action) do |existing, name|
      return if existing.nil?
      return existing if existing == name
      return existing if existing.respond_to?(:name) && existing.name.to_sym == name.to_sym

      nil
    end

    Object.const_set(:RecordingStudioApi, api)
    yield api
  ensure
    Object.send(:remove_const, :RecordingStudioApi) if Object.const_defined?(:RecordingStudioApi, false)
  end

  def define_named_api_behavior(api, api_names)
    configuration = fake_api_configuration(api_names)
    api.define_singleton_method(:configuration) { configuration }
    api.define_singleton_method(:capability_action) do |name, api: :public|
      matching_existing_action(@existing_actions[api.to_s], name)
    end
    api.define_singleton_method(:register_capability_action) do |name, api: :public, **options|
      @registrations << options.merge(name: name, api: api.to_s)
    end
  end

  def fake_action_input_contract_class
    contract_result = Struct.new(:success?, :value, :errors, keyword_init: true)
    Class.new do
      define_method(:initialize) do |definition|
        @fields = definition.fetch(:fields).keys.map(&:to_sym)
      end

      define_method(:call) do |raw_params|
        params = raw_params.to_h.transform_keys(&:to_sym)
        unknown_keys = params.keys - @fields
        errors = unknown_keys.empty? ? [] : ["Unknown parameters: #{unknown_keys.sort.join(', ')}"]
        contract_result.new(success?: errors.empty?, value: errors.empty? ? params : nil, errors: errors)
      end
    end
  end

  def schema_for(action)
    openapi_for(action).dig(:responses, "200", :content, "application/json", :schema)
  end

  def openapi_for(action)
    RecordingStudioAccessible::Api::ACTION_DEFINITIONS.fetch(action).fetch(:openapi)
  end

  def schema_property_names(node)
    return [] if node.nil?

    names = []
    if node.is_a?(Hash)
      properties = node[:properties] || node["properties"]
      if properties.is_a?(Hash)
        names.concat(properties.keys.map(&:to_s))
        properties.each_value { |child| names.concat(schema_property_names(child)) }
      end
      names.concat(schema_property_names(node[:items] || node["items"]))
      Array(node[:oneOf] || node["oneOf"]).each { |child| names.concat(schema_property_names(child)) }
    end
    names.uniq
  end

  def fake_api_configuration(api_names)
    definitions = api_names.map { |name| Struct.new(:name).new(name.to_s) }
    Struct.new(:definitions) do
      def each_api(&)
        definitions.each(&)
      end
    end.new(definitions)
  end
end
