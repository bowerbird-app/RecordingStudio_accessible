# frozen_string_literal: true

# Trashable, Admin, Attachable, Cache, Users, Root Switchable, Metrics,
# Internationalization, and Notifications still require recording_studio
# below 5. Widen that requirement when Bundler loads gemspecs so this app
# can resolve 6.1.0.
module WidenRecordingStudioRequirement
  def add_dependency(name, *requirements)
    if name.to_s == "recording_studio" && requirements.none? { |requirement| requirement.to_s.include?("6") }
      requirements = [">= 6.1.0"]
    end

    super
  end
end

unless Gem::Specification.ancestors.include?(WidenRecordingStudioRequirement)
  Gem::Specification.prepend(WidenRecordingStudioRequirement)
end
