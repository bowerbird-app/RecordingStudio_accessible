# frozen_string_literal: true

module RecordingStudioAccessible
  # The live role list for one recording, and the classes that declared one.
  module RoleLookup
    private

    def names_for(recording)
      klass = class_for(recording)
      return RoleRegistry::BUILT_INS unless klass.respond_to?(:accessible_role_set)

      klass.accessible_role_set.names
    end

    def class_for(recording)
      if recording.respond_to?(:recordable_type) && recording.recordable_type.present?
        found = recording.recordable_type.to_s.safe_constantize
        return found if found
      end
      return recording.recordable.class if recording.respond_to?(:recordable) && recording.recordable

      NilClass
    end

    def each_declared_class
      return unless defined?(ActiveRecord::Base)

      ActiveRecord::Base.descendants.each do |klass|
        next if klass.name.blank?
        next unless klass.instance_variable_defined?(:@accessible_role_set)

        yield klass
      end
    end
  end
end
