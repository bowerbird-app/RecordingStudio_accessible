# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestSignIn
    private

    def sign_in_verified_requester(user)
      return if user.blank? || current_actor.present?

      if respond_to?(:sign_in, true) && defined?(Devise::Mapping)
        sign_in(Devise::Mapping.find_scope!(user), user)
      elsif (warden = request.env["warden"])
        warden.set_user(user, scope: :user)
      end
    end
  end
end
