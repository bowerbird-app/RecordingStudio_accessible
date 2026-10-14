# frozen_string_literal: true

# Stand-in for a sibling gem's Configuration object in ControllerAuth demos/tests.
class ControllerAuthDemoConfig
  class << self
    attr_accessor :authentication_method, :current_actor_method

    def reset!
      @authentication_method = :authenticate_user!
      @current_actor_method = :current_user
    end
  end

  reset!
end
