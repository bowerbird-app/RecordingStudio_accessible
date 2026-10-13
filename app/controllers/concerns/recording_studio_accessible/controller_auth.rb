# frozen_string_literal: true

module RecordingStudioAccessible
  # Shared authenticate / authorize helpers for Recording Studio addon engines.
  #
  # Include and call +recording_studio_auth+ so each gem keeps its familiar
  # +authenticate_<prefix>_actor!+, +<prefix>_actor+, and +current_<prefix>_root+
  # names (hosts can still override those one-liners).
  module ControllerAuth
    extend ActiveSupport::Concern

    UNAUTHORIZED = :unauthorized
    FORBIDDEN = :forbidden

    ACTOR_RESOLUTIONS = %i[current_then_method method_then_current method_only].freeze

    included do
      class_attribute :recording_studio_auth_config_resolver, instance_writer: false
      class_attribute :recording_studio_auth_prefix, instance_writer: false
      class_attribute :recording_studio_auth_options, instance_writer: false, default: {}
    end

    class_methods do
      # Wires authenticate + Current.actor before_actions and defines per-gem
      # one-line delegators so existing host overrides keep working.
      #
      #   class ApplicationController < ActionController::Base
      #     include RecordingStudioAccessible::ControllerAuth
      #
      #     recording_studio_auth(
      #       config: -> { RecordingStudioPresskits.configuration },
      #       prefix: :presskits
      #     )
      #   end
      #
      # Options (sibling gems diverge; defaults match presskits):
      # - +unauthorized_status+ (default +:unauthorized+)
      # - +forbidden_status+ (default +:forbidden+)
      # - +missing_root_status+ (default +:forbidden+)
      # - +missing_actor_status+ on +authorize_recording!+ (default +:unauthorized+)
      # - +response_style+: +:head+ (default), +:plain+, or a callable
      #   +->(status, reason) { ... }+ run with +instance_exec+
      # - +plain_bodies+: optional Hash of reason => body when +:plain+
      # - +set_current_actor+ (default +true+)
      # - +actor_resolution+: +:current_then_method+ (default),
      #   +:method_then_current+, or +:method_only+
      # - +only+ / +except+ / +if+ / +unless+: forwarded to +before_action+
      def recording_studio_auth(config:, prefix:, **options)
        raise ArgumentError, "config: must respond to call" unless config.respond_to?(:call)

        prefix_name = prefix.to_s
        raise ArgumentError, "prefix: must be present" if prefix_name.empty?

        normalized = normalize_recording_studio_auth_options(options)
        self.recording_studio_auth_config_resolver = config
        self.recording_studio_auth_prefix = prefix_name
        self.recording_studio_auth_options = normalized

        define_recording_studio_auth_delegators(prefix_name)
        wire_recording_studio_auth_before_actions(prefix_name, options)
      end

      private

      def normalize_recording_studio_auth_options(options)
        resolution = (options[:actor_resolution] || :current_then_method).to_sym
        unless ACTOR_RESOLUTIONS.include?(resolution)
          raise ArgumentError, "actor_resolution: must be one of #{ACTOR_RESOLUTIONS.join(', ')}"
        end

        {
          unauthorized_status: options.fetch(:unauthorized_status, UNAUTHORIZED),
          forbidden_status: options.fetch(:forbidden_status, FORBIDDEN),
          missing_root_status: options.fetch(:missing_root_status, FORBIDDEN),
          missing_actor_status: options.fetch(:missing_actor_status, UNAUTHORIZED),
          response_style: options.fetch(:response_style, :head),
          plain_bodies: options[:plain_bodies],
          set_current_actor: options.fetch(:set_current_actor, true),
          actor_resolution: resolution
        }
      end

      def define_recording_studio_auth_delegators(prefix_name)
        define_method(:"authenticate_#{prefix_name}_actor!") { authenticate_recording_studio_actor! }
        define_method(:"#{prefix_name}_actor") { recording_studio_actor }
        define_method(:"current_#{prefix_name}_root") { current_recording_studio_root }
        define_method(:"set_#{prefix_name}_current_actor") { set_recording_studio_current_actor }

        helper_method :"current_#{prefix_name}_root"
      end

      def wire_recording_studio_auth_before_actions(prefix_name, options)
        filter_options = options.slice(:only, :except, :if, :unless)
        before_action :"authenticate_#{prefix_name}_actor!", **filter_options
        return unless recording_studio_auth_options[:set_current_actor]

        before_action :"set_#{prefix_name}_current_actor", **filter_options
      end
    end

    # Instance helpers stay private on including controllers (same as gem ApplicationControllers).
    # rubocop:disable Lint/UselessAccessModifier -- Concern instance methods need an explicit private.
    private

    # rubocop:enable Lint/UselessAccessModifier

    def authenticate_recording_studio_actor!
      method_name = recording_studio_auth_configuration&.authentication_method
      return send(method_name) if method_name && respond_to?(method_name, true)

      recording_studio_auth_respond(:unauthorized, status_key: :unauthorized_status)
    end

    def recording_studio_actor
      case recording_studio_auth_option(:actor_resolution)
      when :method_only
        recording_studio_actor_from_configuration
      when :method_then_current
        recording_studio_actor_from_configuration || recording_studio_actor_from_current
      else
        recording_studio_actor_from_current || recording_studio_actor_from_configuration
      end
    end

    def set_recording_studio_current_actor
      return unless defined?(Current) && Current.respond_to?(:actor=)

      Current.actor = recording_studio_auth_named_actor
    end

    def authorize_recording!(recording, role:)
      actor = recording_studio_auth_named_actor
      unless actor
        recording_studio_auth_respond(:missing_actor, status_key: :missing_actor_status)
        return
      end

      return if recording &&
                RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

      recording_studio_auth_respond(:forbidden, status_key: :forbidden_status)
    end

    def current_recording_studio_root
      return current_root_recording if respond_to?(:current_root_recording)

      nil
    end

    def require_root!
      return if recording_studio_auth_named_root.present?

      recording_studio_auth_respond(:missing_root, status_key: :missing_root_status)
    end

    def recording_studio_auth_configuration
      recording_studio_auth_config_resolver&.call
    end

    def recording_studio_auth_option(key)
      (recording_studio_auth_options || {}).fetch(key)
    end

    def recording_studio_auth_named_actor
      prefix = recording_studio_auth_prefix
      return send(:"#{prefix}_actor") if prefix

      recording_studio_actor
    end

    def recording_studio_auth_named_root
      prefix = recording_studio_auth_prefix
      return send(:"current_#{prefix}_root") if prefix

      current_recording_studio_root
    end

    def recording_studio_actor_from_current
      return unless defined?(Current) && Current.respond_to?(:actor)

      Current.actor.presence
    end

    def recording_studio_actor_from_configuration
      method_name = recording_studio_auth_configuration&.current_actor_method
      send(method_name) if method_name && respond_to?(method_name, true)
    end

    def recording_studio_auth_respond(reason, status_key:)
      status = recording_studio_auth_option(status_key)
      style = recording_studio_auth_option(:response_style)

      case style
      when :head
        head status
      when :plain
        render plain: recording_studio_auth_plain_body(reason, status), status: status
      else
        recording_studio_auth_invoke_response_style(style, status, reason)
      end
    end

    def recording_studio_auth_plain_body(reason, status)
      bodies = recording_studio_auth_option(:plain_bodies)
      return bodies[reason] if bodies.is_a?(Hash) && bodies.key?(reason)

      status.to_s.tr("_", " ")
    end

    def recording_studio_auth_invoke_response_style(style, status, reason)
      unless style.respond_to?(:call)
        head status
        return
      end

      if style.arity == 1
        instance_exec(status, &style)
      else
        instance_exec(status, reason, &style)
      end
    end
  end
end
