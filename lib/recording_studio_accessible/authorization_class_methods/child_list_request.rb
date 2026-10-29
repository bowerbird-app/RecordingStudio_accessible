# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    class ChildListFloor
      def self.parse(minimum_role)
        return AnyEffective.new if minimum_role.blank?

        return Closed.new if RecordingStudio::AccessRoles.names_at_or_above(minimum_role).empty?

        AtLeast.new(minimum_role)
      end

      class AnyEffective
        def closed?
          false
        end

        def keep?(resolver)
          resolver.any_effective_grant?
        end
      end

      class Closed
        def closed?
          true
        end

        def keep?(_resolver)
          false
        end
      end

      class AtLeast
        def initialize(minimum_role)
          @minimum_role = minimum_role
        end

        def closed?
          false
        end

        def keep?(resolver)
          RecordingStudio::AccessRoles.satisfies?(
            role: resolver.resolve_role,
            minimum_role: @minimum_role
          )
        end
      end
    end

    class ChildListRequest
      attr_reader :actor, :parent_recording, :floor, :recordable_type_name

      class << self
        def parse(actor:, parent_recording:, minimum_role:, recordable_type:)
          return nil unless actor
          return nil unless parent_recording.is_a?(RecordingStudio::Recording)
          return nil if parent_recording.id.blank?

          type_name = recordable_type_name_for(recordable_type)
          return nil if !recordable_type.nil? && type_name.nil?

          floor = ChildListFloor.parse(minimum_role)
          return nil if floor.closed?

          new(actor, parent_recording, floor, type_name).freeze
        end

        private

        def recordable_type_name_for(recordable_type)
          case recordable_type
          when nil
            nil
          when String
            recordable_type unless recordable_type.blank?
          when Class
            recordable_type.name.presence
          end
        end
      end

      def initialize(actor, parent_recording, floor, recordable_type_name)
        @actor = actor
        @parent_recording = parent_recording
        @floor = floor
        @recordable_type_name = recordable_type_name
      end
    end
    private_constant :ChildListFloor, :ChildListRequest
  end
end
