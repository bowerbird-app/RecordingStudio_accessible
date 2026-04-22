# frozen_string_literal: true

require_relative "hooks"

module RecordingStudioAccessible
  class Configuration
    attr_accessor :warn_on_core_conflict,
                  :access_management_actor_scope,
                  :access_management_actor_label,
                  :access_management_actor_email_resolver,
                  :access_management_authorizer
    attr_reader :hooks

    def initialize
      @warn_on_core_conflict = true
      @access_management_actor_scope = method(:default_access_management_actor_scope)
      @access_management_actor_label = method(:default_access_management_actor_label)
      @access_management_actor_email_resolver = method(:default_access_management_actor_email_resolver)
      @access_management_authorizer = method(:default_access_management_authorizer)
      @hooks = Hooks.new
    end

    def to_h
      {
        warn_on_core_conflict: warn_on_core_conflict,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, cast_boolean(v)) if key == "warn_on_core_conflict" && respond_to?(setter)
      end
    end

    def grantable_actors_for(controller:)
      Array(resolve_configurable(access_management_actor_scope, controller))
    end

    def actor_label_for(actor)
      resolve_configurable(access_management_actor_label, actor)
    end

    def resolve_actor_for_email(controller:, email:)
      resolve_configurable(access_management_actor_email_resolver, controller: controller, email: email)
    end

    def authorize_access_management?(controller:, recording:)
      resolve_configurable(access_management_authorizer, controller: controller, recording: recording)
    end

    private

    def default_access_management_actor_scope(controller)
      return [] unless defined?(::User)

      scope = ::User.all
      return scope.order(:email) if scope.respond_to?(:order) && ::User.column_names.include?("email")

      scope
    rescue StandardError
      []
    end

    def default_access_management_actor_label(actor)
      return "Unknown actor" unless actor

      actor_name = if actor.respond_to?(:email)
                     actor.email.to_s.squish.presence
                   elsif actor.respond_to?(:name)
                     actor.name.to_s.squish.presence
                   end

      actor_name || "#{actor.class.name.demodulize} ##{actor.id}"
    end

    def default_access_management_actor_email_resolver(controller:, email:)
      return nil unless controller
      return nil unless defined?(::User)
      return nil unless ::User.respond_to?(:column_names)
      return nil unless ::User.column_names.include?("email")

      normalized_email = email.to_s.strip.downcase
      return nil if normalized_email.blank?

      if ::User.respond_to?(:where)
        ::User.where("LOWER(email) = ?", normalized_email).first
      elsif ::User.respond_to?(:find_by)
        ::User.find_by(email: normalized_email)
      end
    rescue StandardError
      nil
    end

    def default_access_management_authorizer(controller:, recording:)
      return false unless defined?(::RecordingStudio::Services::AccessCheck)

      actor = controller.respond_to?(:current_user, true) ? controller.send(:current_user) : nil
      return false unless actor && recording

      RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: recording, role: :admin)
    end

    def resolve_configurable(callable, *, **kwargs)
      return unless callable

      if kwargs.any?
        callable.call(*, **kwargs)
      else
        callable.call(*)
      end
    end

    def cast_boolean(value)
      if defined?(ActiveModel::Type::Boolean)
        ActiveModel::Type::Boolean.new.cast(value)
      else
        !!value
      end
    end
  end
end
