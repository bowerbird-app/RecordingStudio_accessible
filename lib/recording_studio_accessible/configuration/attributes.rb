# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Attributes
      ACCESSORS = %i[
        warn_on_core_conflict
        avatar_resolver
        access_management_actor_scope
        access_management_current_actor_resolver
        access_management_actor_label
        access_management_actor_email_resolver
        access_management_missing_actor_handler
        access_management_access_granted_notifier
        access_management_access_granted_subject
        access_management_access_granted_url_resolver
        access_invitation_ttl
        access_invitation_actor_matcher
        access_invitation_notifier
        access_invitation_subject
        access_invitation_url_resolver
        access_invitation_sign_in_url_resolver
        access_notification_locale
        access_management_authorizer
        access_request_submitted_notifier
        access_request_denied_notifier
        access_request_index_recordings
        mounted_page_authorizer
        authorize_actor_through
      ].freeze
      READERS = %i[hooks access_actor_types action_audiences access_request_gates layout].freeze

      def self.included(base)
        base.attr_accessor(*ACCESSORS)
        base.attr_reader(*READERS)
      end
    end
  end
end
