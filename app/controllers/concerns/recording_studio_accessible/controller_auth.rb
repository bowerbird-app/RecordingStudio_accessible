# frozen_string_literal: true

module RecordingStudioAccessible
  # Shared authenticate / authorize helpers for Recording Studio addon engines.
  #
  # Include and call +recording_studio_auth+ so each gem keeps its familiar
  # prefixed (or renamed) helpers. Generated methods are private so Rails does
  # not treat them as actions.
  module ControllerAuth
    extend ActiveSupport::Concern

    UNAUTHORIZED = :unauthorized
    FORBIDDEN = :forbidden
    PREFIX_FORMAT = /\A[a-z_][a-z0-9_]*\z/
    ACTOR_RESOLUTIONS = %i[
      current_then_method
      method_then_current
      method_only
      configured_as_is
    ].freeze

    included do
      class_attribute :recording_studio_auth_config_resolver,
                      instance_reader: false,
                      instance_writer: false
      class_attribute :recording_studio_auth_prefix,
                      instance_reader: false,
                      instance_writer: false
      class_attribute :recording_studio_auth_options,
                      instance_reader: false,
                      instance_writer: false,
                      default: {}.freeze
    end

    class_methods do
      # Wires authenticate + Current.actor before_actions and defines private
      # one-line helpers so host overrides keep working.
      #
      # Options (sibling gems diverge; defaults match presskits):
      # - +authenticate+ (default +true+) — set +false+ to skip the authenticate
      #   before_action (stripe)
      # - +authenticate_method+ / +actor_method+ / +set_current_actor_method+ /
      #   +root_method+ — override generated names (site_settings)
      # - +actor_resolution+: +:current_then_method+ (default),
      #   +:method_then_current+, +:method_only+, or +:configured_as_is+
      #   (configured method result as-is; nil stays nil; no Current fallback)
      # - +actor_resolver+ / +root_resolver+ — optional callables (stripe)
      # - +require_actor+ — when true, +require_root!+ checks actor first
      # - +on_missing_actor_for_root+ — callable for that failure (redirect/flash)
      # - status / +response_style+ / +plain_bodies+ — response shape knobs
      # - +only+ / +except+ / +if+ / +unless+ — forwarded to +before_action+
      def recording_studio_auth(config:, prefix:, **options)
        raise ArgumentError, "recording_studio_auth already configured on #{name}" if recording_studio_auth_configured?
        raise ArgumentError, "config: must respond to call" unless config.respond_to?(:call)

        prefix_name = prefix.to_s
        raise ArgumentError, "prefix: must match #{PREFIX_FORMAT.inspect}" unless prefix_name.match?(PREFIX_FORMAT)

        normalized = normalize_recording_studio_auth_options(prefix_name, options)
        self.recording_studio_auth_config_resolver = config
        self.recording_studio_auth_prefix = prefix_name
        self.recording_studio_auth_options = normalized

        define_recording_studio_auth_delegators(normalized)
        wire_recording_studio_auth_before_actions(normalized, options)
      end

      private

      def recording_studio_auth_configured?
        !recording_studio_auth_config_resolver.nil?
      end

      def normalize_recording_studio_auth_options(prefix_name, options)
        resolution = (options[:actor_resolution] || :current_then_method).to_sym
        unless ACTOR_RESOLUTIONS.include?(resolution)
          raise ArgumentError, "actor_resolution: must be one of #{ACTOR_RESOLUTIONS.join(', ')}"
        end

        authenticate_method = (options[:authenticate_method] || "authenticate_#{prefix_name}_actor!").to_sym
        actor_method = (options[:actor_method] || "#{prefix_name}_actor").to_sym
        set_current_actor_method = (options[:set_current_actor_method] || "set_#{prefix_name}_current_actor").to_sym
        root_method = (options[:root_method] || "current_#{prefix_name}_root").to_sym
        plain_bodies = options[:plain_bodies]
        plain_bodies = plain_bodies.dup.freeze if plain_bodies.is_a?(Hash)

        {
          authenticate: options.fetch(:authenticate, true),
          authenticate_method: authenticate_method,
          actor_method: actor_method,
          set_current_actor_method: set_current_actor_method,
          root_method: root_method,
          unauthorized_status: options.fetch(:unauthorized_status, UNAUTHORIZED),
          forbidden_status: options.fetch(:forbidden_status, FORBIDDEN),
          missing_root_status: options.fetch(:missing_root_status, FORBIDDEN),
          missing_actor_status: options.fetch(:missing_actor_status, UNAUTHORIZED),
          response_style: options.fetch(:response_style, :head),
          plain_bodies: plain_bodies,
          set_current_actor: options.fetch(:set_current_actor, true),
          actor_resolution: resolution,
          actor_resolver: options[:actor_resolver],
          root_resolver: options[:root_resolver],
          require_actor: options.fetch(:require_actor, false),
          on_missing_actor_for_root: options[:on_missing_actor_for_root]
        }.freeze
      end

      def define_recording_studio_auth_delegators(normalized)
        authenticate_method = normalized[:authenticate_method]
        actor_method = normalized[:actor_method]
        set_current_actor_method = normalized[:set_current_actor_method]
        root_method = normalized[:root_method]

        define_method(authenticate_method) { authenticate_recording_studio_actor! }
        define_method(actor_method) { recording_studio_actor }
        define_method(set_current_actor_method) { set_recording_studio_current_actor }
        define_method(root_method) { current_recording_studio_root }

        private authenticate_method, actor_method, set_current_actor_method, root_method
        helper_method root_method
      end

      def wire_recording_studio_auth_before_actions(normalized, options)
        filter_options = options.slice(:only, :except, :if, :unless)
        before_action normalized[:authenticate_method], **filter_options if normalized[:authenticate]
        return unless normalized[:set_current_actor]

        before_action normalized[:set_current_actor_method], **filter_options
      end
    end

    # Instance helpers stay private on including controllers.
    # rubocop:disable Lint/UselessAccessModifier -- Concern instance methods need an explicit private.
    private

    # rubocop:enable Lint/UselessAccessModifier

    def authenticate_recording_studio_actor!
      method_name = recording_studio_auth_configuration&.authentication_method
      return send(method_name) if method_name && respond_to?(method_name, true)

      if method_name
        Rails.logger.warn(
          "[RecordingStudioAccessible] ControllerAuth authentication_method " \
          "#{method_name.inspect} is not defined on #{self.class.name}"
        )
      end

      recording_studio_auth_respond(:unauthorized, status_key: :unauthorized_status)
    end

    def recording_studio_actor
      resolver = recording_studio_auth_option(:actor_resolver)
      return instance_exec(&resolver) if resolver.respond_to?(:call)

      case recording_studio_auth_option(:actor_resolution)
      when :method_only, :configured_as_is
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
      resolver = recording_studio_auth_option(:root_resolver)
      return instance_exec(&resolver) if resolver.respond_to?(:call)
      return current_root_recording if respond_to?(:current_root_recording)

      nil
    end

    def require_root!
      if recording_studio_auth_option(:require_actor) && recording_studio_auth_named_actor.blank?
        respond_missing_actor_for_root
        return
      end
      return if recording_studio_auth_named_root.present?

      recording_studio_auth_respond(:missing_root, status_key: :missing_root_status)
    end

    def respond_missing_actor_for_root
      handler = recording_studio_auth_option(:on_missing_actor_for_root)
      if handler.respond_to?(:call)
        instance_exec(&handler)
      else
        recording_studio_auth_respond(:missing_actor_for_root, status_key: :missing_actor_status)
      end
    end

    def recording_studio_auth_configuration
      self.class.recording_studio_auth_config_resolver&.call
    end

    def recording_studio_auth_option(key)
      self.class.recording_studio_auth_options.fetch(key)
    end

    def recording_studio_auth_named_actor
      send(recording_studio_auth_option(:actor_method))
    end

    def recording_studio_auth_named_root
      send(recording_studio_auth_option(:root_method))
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
