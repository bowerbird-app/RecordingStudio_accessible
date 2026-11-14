# frozen_string_literal: true

require "recording_studio_accessible/actor_type"
require "recording_studio_accessible/dependent_access"
require "recording_studio_accessible/direct_access_query"
require "recording_studio_accessible/extracted/recording_studio/access_roles"
require "recording_studio_accessible/extracted/recording_studio/services/access_path"

module RecordingStudioAccessible
  # An actor and the strongest effective role they hold on a recording.
  ActorAccess = Struct.new(:actor, :role, keyword_init: true)

  # Effective roles for every actor on a recording.
  #
  # Uses the same path as role_for (the recording, its ancestors, and
  # root_recording_or_self) and one kept-grant query over that set.
  # Invitations and audience gates are not grants and are left out.
  class ActorsWithAccess
    def initialize(recording)
      @recording = recording
    end

    def entries(minimum_role: :view)
      return [] unless recording

      selected = roles_by_key.select { |_key, role| role_satisfies?(role, minimum_role) }
      selected.filter_map { |key, role| entry_for(key, role) }
              .sort_by { |entry| [ActorType.for(entry.actor), entry.actor.id.to_s] }
    end

    def grants
      @grants ||= load_grants
    end

    def effective_grant?(access_recording)
      effective_grants[access_recording&.id] == true
    end

    def actor_at(actor_type, actor_id)
      actors_by_key[actor_key(actor_type, actor_id)]
    end

    def effective_role_for(actor)
      return unless actor

      roles_by_key[actor_key(ActorType.for(actor), actor.id)]
    end

    private

    attr_reader :recording

    def entry_for(key, role)
      actor = actors_by_key[key]
      ActorAccess.new(actor: actor, role: role) if actor
    end

    def load_grants
      return [] unless recording

      path = RecordingStudio::Services::AccessPath.new(recording: recording).build
      @path_recordings = path.path_recordings
      DirectAccessQuery.access_recordings_for_parents(path.lookup_recordings).to_a
    end

    def effective_grants
      @effective_grants ||= grants.to_h { |grant| [grant.id, DependentAccess.effective?(grant)] }
    end

    def roles_by_key
      @roles_by_key ||= grants.each_with_object({}) { |grant, best| remember_role(best, grant) }
    end

    def remember_role(best, grant)
      role = role_for_grant(grant)
      key = key_for_grant(grant)
      return unless role && key
      return if outranked?(best[key], role)

      best[key] = role
    end

    def role_for_grant(grant)
      return unless effective_grant?(grant)

      ranked_role(grant.recordable&.role)
    end

    def outranked?(current, candidate)
      current && role_rank(current) >= role_rank(candidate)
    end

    def ranked_role(role)
      name = RecordingStudio::AccessRoles.normalize(role)
      return if name.blank?
      return unless RecordingStudio::AccessRoles.value_for(name)

      name.to_sym
    end

    def role_rank(role)
      RecordingStudio::AccessRoles.value_for(role)
    end

    def role_satisfies?(role, minimum_role)
      RecordingStudio::AccessRoles.satisfies?(role: role, minimum_role: minimum_role)
    end

    def actors_by_key
      @actors_by_key ||= actor_keys.group_by(&:first).each_with_object({}) do |(type, pairs), loaded|
        assign_actors(loaded, type, pairs)
      end
    end

    def assign_actors(loaded, type, pairs)
      klass = actor_class(type)
      return unless klass

      klass.where(id: pairs.map(&:last)).each do |actor|
        loaded[actor_key(type, actor.id)] = actor
      end
    end

    def actor_keys
      grants.filter_map { |grant| key_for_grant(grant) }.uniq
    end

    def key_for_grant(grant)
      access = grant.recordable
      return unless access

      key = actor_key(access.actor_type, access.actor_id)
      key unless key.any?(&:blank?)
    end

    def actor_key(type, id)
      [type.to_s, id.to_s]
    end

    def actor_class(type)
      klass = type.to_s.safe_constantize
      return unless klass.is_a?(Class)
      return unless klass < ActiveRecord::Base

      klass
    end
  end

  require "recording_studio_accessible/actors_with_access/stored_grants"

  class ActorsWithAccess
    include StoredGrants
  end
end
