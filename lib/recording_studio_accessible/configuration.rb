# frozen_string_literal: true

require_relative "hooks"

module RecordingStudioAccessible
  class MissingActorResolution
    attr_reader :status, :actor, :location, :notice, :alert, :error

    def self.found(actor:, notice: nil)
      new(status: :found, actor: actor, notice: notice)
    end

    def self.created(actor:, notice: nil)
      new(status: :created, actor: actor, notice: notice)
    end

    def self.invited(notice: nil)
      new(status: :invited, notice: notice)
    end

    def self.invalid(error:)
      new(status: :invalid, error: error)
    end

    def self.redirect(location:, notice: nil, alert: nil, status: :redirect)
      new(status: status, location: location, notice: notice, alert: alert)
    end

    def initialize(status:, actor: nil, location: nil, notice: nil, alert: nil, error: nil)
      @status = status.to_sym
      @actor = actor
      @location = location
      @notice = notice
      @alert = alert
      @error = error
    end
  end

  class Configuration
    attr_accessor :warn_on_core_conflict,
                  :access_management_actor_scope,
                  :access_management_current_actor_resolver,
                  :access_management_actor_label,
                  :access_management_actor_email_resolver,
                  :access_management_missing_actor_handler,
                  :access_management_access_granted_notifier,
                  :access_management_access_granted_subject,
                  :access_management_access_granted_url_resolver,
                  :access_management_authorizer,
                  :mounted_page_authorizer
    attr_reader :hooks

    def initialize
      @warn_on_core_conflict = true
      @access_management_actor_scope = method(:default_access_management_actor_scope)
      @access_management_current_actor_resolver = method(:default_access_management_current_actor_resolver)
      @access_management_actor_label = method(:default_access_management_actor_label)
      @access_management_actor_email_resolver = method(:default_access_management_actor_email_resolver)
      @access_management_missing_actor_handler = method(:default_access_management_missing_actor_handler)
      @access_management_access_granted_notifier = method(:default_access_management_access_granted_notifier)
      @access_management_access_granted_subject = method(:default_access_management_access_granted_subject)
      @access_management_access_granted_url_resolver = method(:default_access_management_access_granted_url_resolver)
      @access_management_authorizer = method(:default_access_management_authorizer)
      @mounted_page_authorizer = method(:default_mounted_page_authorizer)
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

    def current_actor_for(controller: nil)
      resolve_configurable(access_management_current_actor_resolver, controller: controller)
    end

    def resolve_actor_for_email(controller:, email:)
      resolve_configurable(access_management_actor_email_resolver, controller: controller, email: email)
    end

    def resolve_missing_actor(controller:, email:, recording:, role:, manager_actor:)
      result = resolve_configurable(
        access_management_missing_actor_handler,
        controller: controller,
        email: email,
        recording: recording,
        role: role,
        manager_actor: manager_actor
      )

      normalize_missing_actor_resolution(result, email: email)
    end

    def missing_actor_error_for_email(email:)
      default_missing_actor_error_for_email(email: email)
    end

    def authorize_access_management?(recording:, actor: nil, controller: nil)
      call_access_management_authorizer(recording: recording, actor: actor, controller: controller)
    end

    def authorize_mounted_page?(controller:, actor: nil, recording: nil)
      call_mounted_page_authorizer(controller: controller, actor: actor, recording: recording)
    end

    def notify_access_granted(controller:, recording:, actor:, role:, manager_actor:)
      resolve_configurable(
        access_management_access_granted_notifier,
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    def access_granted_subject_for(controller:, recording:, actor:, role:, manager_actor:)
      resolve_access_granted_subject(
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    def access_granted_url_for(controller:, recording:, actor:, role:, manager_actor:)
      resolve_access_granted_url(
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    private

    def default_access_management_actor_scope(_controller)
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

    def default_access_management_current_actor_resolver(controller: nil)
      current_actor = Current.actor if defined?(Current) && Current.respond_to?(:actor)
      return current_actor if current_actor.present?
      return unless controller.respond_to?(:current_user, true)

      controller.send(:current_user)
    rescue StandardError
      nil
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

    def default_access_management_missing_actor_handler(email:, controller: nil, recording: nil, role: nil,
                                                        manager_actor: nil)
      _controller = controller
      _recording = recording
      _role = role
      _manager_actor = manager_actor
      normalized_email = email.to_s.strip.downcase
      if normalized_email.blank?
        return MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: email))
      end

      MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: normalized_email))
    rescue StandardError
      MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: normalized_email))
    end

    def default_access_management_access_granted_notifier(controller:, recording:, actor:, role:, manager_actor:)
      return unless actor.respond_to?(:email)

      recipient_email = actor.email.to_s.strip
      return if recipient_email.blank?

      return unless defined?(RecordingStudioAccessible::AccessGrantedMailer)

      mail = RecordingStudioAccessible::AccessGrantedMailer.with(
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor,
        subject: access_granted_subject_for(
          controller: controller,
          recording: recording,
          actor: actor,
          role: role,
          manager_actor: manager_actor
        ),
        access_url: access_granted_url_for(
          controller: controller,
          recording: recording,
          actor: actor,
          role: role,
          manager_actor: manager_actor
        )
      ).access_granted

      deliver_notification(mail)
    rescue StandardError
      nil
    end

    def default_access_management_authorizer(recording:, controller: nil, actor: nil)
      actor ||= current_actor_for(controller: controller)
      return false unless actor && recording

      RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :admin)
    end

    def default_mounted_page_authorizer(controller:, actor: nil, recording: nil)
      actor ||= current_actor_for(controller: controller)
      return false unless actor && recording

      RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :admin)
    end

    def call_access_management_authorizer(recording:, actor:, controller:)
      callable = access_management_authorizer
      return false unless callable

      kwargs = {
        recording: recording,
        actor: actor,
        controller: controller
      }

      callable.call(**filtered_keyword_arguments(callable, kwargs))
    end

    def call_mounted_page_authorizer(controller:, actor:, recording:)
      callable = mounted_page_authorizer
      return false unless callable

      kwargs = {
        controller: controller,
        actor: actor,
        recording: recording
      }

      callable.call(**filtered_keyword_arguments(callable, kwargs))
    end

    def default_missing_actor_error_for_email(email:)
      normalized_email = email.to_s.strip
      return "User is required" if normalized_email.blank?

      "User with email #{normalized_email} was not found"
    end

    def default_missing_actor_notice_for_email(email:)
      "Access granted to #{email}"
    end

    def default_access_management_access_granted_subject(recording:, controller: nil, actor: nil, role: nil,
                                                         manager_actor: nil)
      _controller = controller
      _actor = actor
      _role = role
      _manager_actor = manager_actor
      recording_label = if defined?(::RecordingStudio::Labels) && recording.respond_to?(:recordable)
                          ::RecordingStudio::Labels.title_for(recording.recordable)
                        end

      return "You were given access" if recording_label.blank?

      "You were given access to #{recording_label}"
    rescue StandardError
      "You were given access"
    end

    def normalize_missing_actor_resolution(result, email:)
      return MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: email)) if result.nil?
      return result if result.is_a?(MissingActorResolution)
      return normalize_missing_actor_resolution_hash(result, email: email) if result.is_a?(Hash)

      MissingActorResolution.found(actor: result)
    end

    def normalize_missing_actor_resolution_hash(result, email:)
      attributes = result.transform_keys(&:to_sym)
      status = (attributes[:status] || :invalid).to_sym

      if %i[redirect
            requires_resolution].include?(status) && attributes[:location].present?
        return MissingActorResolution.redirect(location: attributes[:location],
                                               notice: attributes[:notice],
                                               alert: attributes[:alert],
                                               status: status)
      end

      if attributes[:actor].present? || attributes[:error].present? || status == :invited
        return MissingActorResolution.new(**attributes)
      end

      MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: email))
    end

    def default_access_management_access_granted_url_resolver(controller:, recording: nil, actor: nil, role: nil,
                                                              manager_actor: nil)
      _recording = recording
      _actor = actor
      _role = role
      _manager_actor = manager_actor
      return unless controller.respond_to?(:main_app)
      return unless controller.main_app.respond_to?(:root_url)

      recordable_url = resolve_recordable_access_url(controller: controller, recording: recording)
      return recordable_url if recordable_url.present?

      controller.main_app.root_url
    rescue StandardError
      nil
    end

    def resolve_recordable_access_url(controller:, recording:)
      return unless recording

      candidates = [recording.recordable, recording.root_recording&.recordable].compact.uniq

      candidates.each do |recordable|
        url = polymorphic_access_url_for(controller: controller, recordable: recordable)
        return url if url.present?
      end

      nil
    end

    def polymorphic_access_url_for(controller:, recordable:)
      return unless recordable

      route_proxy = controller.main_app
      return unless route_proxy.respond_to?(:polymorphic_url)

      route_proxy.polymorphic_url(recordable)
    rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
      nil
    end

    def resolve_access_granted_url(controller:, recording:, actor:, role:, manager_actor:)
      resolve_configurable(
        access_management_access_granted_url_resolver,
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    def resolve_access_granted_subject(controller:, recording:, actor:, role:, manager_actor:)
      resolve_configurable(
        access_management_access_granted_subject,
        controller: controller,
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    def deliver_notification(mail)
      return unless mail

      if mail.respond_to?(:deliver_now)
        mail.deliver_now
      elsif mail.respond_to?(:deliver_later)
        mail.deliver_later
      end
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

    def filtered_keyword_arguments(callable, kwargs)
      parameters = callable.parameters
      return kwargs if parameters.any? { |type, _name| type == :keyrest }

      supported_keys = parameters.filter_map do |type, name|
        name if %i[key keyreq].include?(type)
      end

      kwargs.slice(*supported_keys)
    end
  end
end
