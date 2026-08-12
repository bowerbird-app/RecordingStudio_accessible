# frozen_string_literal: true

namespace :recording_studio_accessible do
  namespace :access_grants do
    desc "Inspect duplicate direct access grants; set DRY_RUN=false and MANAGER_ACTOR_GID to repair"
    task integrity: :environment do
      dry_run = ENV.fetch("DRY_RUN", "true") != "false"
      manager_actor_gid = ENV["MANAGER_ACTOR_GID"].presence
      manager_actor = GlobalID::Locator.locate(manager_actor_gid) if manager_actor_gid

      if !dry_run && manager_actor.nil?
        abort "MANAGER_ACTOR_GID must identify a persisted manager actor when DRY_RUN=false"
      end

      result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call(
        dry_run: dry_run,
        manager_actor: manager_actor
      )

      report = result.value&.fetch(:report, []) || []
      report.each { |entry| puts entry.inspect }

      if result.failure?
        warn result.error
        result.errors.each { |error| warn error.inspect }
        abort
      end

      puts "#{report.length} duplicate access grant group(s) inspected#{dry_run ? ' (dry run)' : ' and repaired'}"
    end
  end
end