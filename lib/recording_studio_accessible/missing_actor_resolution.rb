# frozen_string_literal: true

module RecordingStudioAccessible
  class MissingActorResolution
    FIELDS = %i[status actor location notice alert error].freeze

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

    def self.unresolved(notice: nil)
      new(status: :unresolved, notice: notice)
    end

    def self.invalid(error:)
      new(status: :invalid, error: error)
    end

    def self.redirect(location:, notice: nil, alert: nil, status: :redirect)
      new(status: status, location: location, notice: notice, alert: alert)
    end

    def initialize(**attrs)
      unknown = attrs.keys - FIELDS
      raise ArgumentError, "unknown keyword: #{unknown.first.inspect}" if unknown.any?
      raise ArgumentError, "missing keyword: :status" unless attrs.key?(:status)

      @status = attrs[:status].to_sym
      @actor = attrs[:actor]
      @location = attrs[:location]
      @notice = attrs[:notice]
      @alert = attrs[:alert]
      @error = attrs[:error]
    end
  end
end
