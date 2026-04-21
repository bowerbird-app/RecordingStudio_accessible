# frozen_string_literal: true

require_relative "hooks"

module RecordingStudioAccessible
  class Configuration
    attr_accessor :warn_on_core_conflict
    attr_reader :hooks

    def initialize
      @warn_on_core_conflict = true
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

    private

    def cast_boolean(value)
      if defined?(ActiveModel::Type::Boolean)
        ActiveModel::Type::Boolean.new.cast(value)
      else
        !!value
      end
    end
  end
end
