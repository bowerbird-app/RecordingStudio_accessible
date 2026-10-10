# frozen_string_literal: true

module RecordingStudioAccessible
  class ActionAudiences
    include Enumerable

    attr_accessor :on_change

    def initialize
      @mutex = Mutex.new
      @entries = {}
    end

    def [](action)
      return nil unless valid_action?(action)

      @mutex.synchronize { dup_entry(@entries[action]) }
    end

    def []=(action, value)
      normalized_action = normalize_action!(action)
      entry = normalize_entry(value)

      @mutex.synchronize do
        @entries[normalized_action] = entry
      end

      notify_change(normalized_action)
      entry.nil? ? nil : dup_entry(entry)
    end

    def replace(hash)
      normalized = {}
      Array(hash).each do |action, value|
        next unless valid_action?(action)

        normalized[action] = normalize_entry(value)
      end

      @mutex.synchronize do
        @entries.replace(normalized)
      end

      normalized.each_key { |action| notify_change(action) }

      to_h
    end

    def key?(action)
      return false unless valid_action?(action)

      @mutex.synchronize { @entries.key?(action) }
    end
    alias configured? key?

    def keys
      @mutex.synchronize { @entries.keys.sort_by(&:to_s) }
    end

    def to_h
      @mutex.synchronize do
        @entries.keys.sort_by(&:to_s).to_h do |action|
          [action, dup_entry(@entries.fetch(action))]
        end
      end
    end

    def each(&)
      to_h.each(&)
    end

    def each_key(&)
      keys.each(&)
    end

    def clear!
      @mutex.synchronize { @entries.clear }
    end

    def empty?
      @mutex.synchronize { @entries.empty? }
    end

    private

    def notify_change(action)
      on_change&.call(action)
    rescue StandardError
      nil
    end

    def normalize_action!(action)
      raise ArgumentError, "action name must be a non-blank symbol" unless valid_action?(action)

      action
    end

    def valid_action?(action)
      action.is_a?(Symbol) && !action.to_s.strip.empty?
    end

    def normalize_entry(value)
      return nil if value.nil?

      attributes = value.respond_to?(:to_h) ? value.to_h : {}
      attributes = attributes.transform_keys { |key| key.to_s.to_sym }

      allowed = normalize_names(attributes[:allowed])
      allowed |= [AudienceRegistry::GRANTED]

      {
        allowed: allowed,
        default: normalize_name(attributes[:default]),
        granted_roles: normalize_names(attributes[:granted_roles]),
        granted_override: cast_flag(attributes.fetch(:granted_override, false)),
        manage_role: normalize_name(attributes[:manage_role]) || :admin
      }
    rescue StandardError
      nil
    end

    def normalize_names(values)
      Array(values).filter_map { |value| normalize_name(value) }
    end

    def normalize_name(value)
      return if value.nil?

      name = value.is_a?(Symbol) ? value : value.to_s.strip.to_sym
      return if name.to_s.strip.empty?

      name
    rescue StandardError
      nil
    end

    def cast_flag(value)
      if defined?(ActiveModel::Type::Boolean)
        ActiveModel::Type::Boolean.new.cast(value) ? true : false
      else
        value == true
      end
    end

    def dup_entry(entry)
      return nil if entry.nil?

      {
        allowed: Array(entry[:allowed]).dup,
        default: entry[:default],
        granted_roles: Array(entry[:granted_roles]).dup,
        granted_override: entry[:granted_override] ? true : false,
        manage_role: entry[:manage_role]
      }
    end
  end
end
