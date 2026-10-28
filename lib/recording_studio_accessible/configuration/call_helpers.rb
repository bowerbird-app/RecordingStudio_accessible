# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module CallHelpers
      private

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

      def fetch_keywords(kwargs, names)
        unknown = kwargs.keys - names
        raise ArgumentError, "unknown keyword: #{unknown.first.inspect}" if unknown.any?

        names.to_h { |name| [name, kwargs.fetch(name)] }
      rescue KeyError => e
        raise ArgumentError, "missing keyword: #{e.key.inspect}"
      end

      def invitation_delivery_succeeded?(result)
        return false if result.nil? || result == false
        return result.success? if result.respond_to?(:success?)

        true
      end

      def deliver_notification(mail, locale: I18n.locale)
        return unless mail

        I18n.with_locale(locale) do
          if mail.respond_to?(:deliver_now)
            mail.deliver_now
          elsif mail.respond_to?(:deliver_later)
            mail.deliver_later
          end
        end
      end
    end
  end
end
