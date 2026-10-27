# frozen_string_literal: true

class CurrentActorResolversController < ApplicationController
  def show
    actor = RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    render plain: [
      "resolver=#{actor&.email}",
      "current_actor=#{Current.actor&.email}",
      "current_user=#{current_user&.email}"
    ].join(" "), layout: false
  end
end
