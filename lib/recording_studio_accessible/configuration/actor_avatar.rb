# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module ActorAvatar
      def actor_avatar_src_for(actor)
        extract_image_src(resolve_configurable(access_management_actor_avatar, actor))
      rescue StandardError
        nil
      end

      private

      def default_access_management_actor_avatar(actor)
        return unless actor

        named_image_src(actor) || avatar_resolver_src(actor) || recording_studio_user_profile_image_src(actor)
      end

      def avatar_resolver_src(actor)
        avatar_for(actor)&.[](:src)
      rescue StandardError
        nil
      end

      def recording_studio_user_profile_image_src(actor)
        src_from_users_profile_image_recording(actor) || named_image_src(recording_studio_user_profile(actor))
      end

      def src_from_users_profile_image_recording(actor)
        return unless defined?(::RecordingStudioUser)
        return unless RecordingStudioUser.respond_to?(:profile_image_recording_for)

        named_or_attached_image_src(RecordingStudioUser.profile_image_recording_for(actor))
      rescue StandardError
        nil
      end

      def named_or_attached_image_src(recording)
        return if recording.blank?

        extract_image_src(recording) || named_image_src(recording) || src_from_attachment_recording(recording)
      end

      def named_image_src(object)
        extract_image_src(read_actor_attribute(object, :avatar)) ||
          extract_image_src(read_actor_attribute(object, :image))
      end

      def src_from_attachment_recording(recording)
        attachment = recording.respond_to?(:recordable) ? recording.recordable : recording
        attached_file_src(read_actor_attribute(attachment, :file))
      end

      def attached_file_src(file)
        return unless file
        return if file.respond_to?(:attached?) && !file.attached?

        blob = read_actor_attribute(file, :blob) || file
        rails_blob_src(blob)
      end

      def rails_blob_src(blob)
        return unless blob
        return unless defined?(Rails)
        return unless Rails.application&.routes&.url_helpers.respond_to?(:rails_blob_path)

        Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      rescue StandardError
        nil
      end

      def extract_image_src(value)
        string_or_hash_src(value) || object_image_src(value)
      end

      def string_or_hash_src(value)
        return safe_avatar_image_url(value) if value.is_a?(String)
        return unless value.is_a?(Hash)

        string_or_hash_src(hash_image_candidate(value))
      end

      def hash_image_candidate(value)
        value[:src] || value["src"] || value[:image_url] || value["image_url"] || value[:url] || value["url"]
      end

      def object_image_src(value)
        return if value.nil? || value == false || value.is_a?(String) || value.is_a?(Hash)

        string_or_hash_src(read_actor_attribute(value, :url)) ||
          string_or_hash_src(read_actor_attribute(value, :src)) ||
          string_or_hash_src(read_actor_attribute(value, :image_url))
      end
    end
  end
end
