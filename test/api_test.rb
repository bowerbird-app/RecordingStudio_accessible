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

  def fake_api_configuration(api_names)
    definitions = api_names.map { |name| Struct.new(:name).new(name.to_s) }
    Struct.new(:definitions) do
      def each_api(&)
        definitions.each(&)
      end
    end.new(definitions)
  end
end
