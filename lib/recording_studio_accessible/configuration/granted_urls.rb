# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module GrantedUrls
      private

      def default_access_management_access_granted_url_resolver(**kwargs)
        controller = kwargs[:controller]
        return unless controller.respond_to?(:main_app)
        return unless controller.main_app.respond_to?(:root_url)

        recordable_url = resolve_recordable_access_url(controller: controller, recording: kwargs[:recording])
        return recordable_url if recordable_url.present?

        controller.main_app.root_url
      rescue StandardError
        nil
      end

      def resolve_recordable_access_url(controller:, recording:)
        return unless recording

        recordable_url_candidates(recording).each do |recordable|
          url = polymorphic_access_url_for(controller: controller, recordable: recordable)
          return url if url.present?
        end

        nil
      end

      def recordable_url_candidates(recording)
        [recording.recordable, recording.root_recording&.recordable].compact.uniq
      end

      def polymorphic_access_url_for(controller:, recordable:)
        return unless recordable

        route_proxy = controller.main_app
        return unless route_proxy.respond_to?(:polymorphic_url)

        route_proxy.polymorphic_url(recordable)
      rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
        nil
      end
    end
  end
end
