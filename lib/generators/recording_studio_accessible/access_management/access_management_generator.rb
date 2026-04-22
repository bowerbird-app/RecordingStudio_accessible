# frozen_string_literal: true

require "rails/generators"

module RecordingStudioAccessible
  module Generators
    class AccessManagementGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Sets up the mounted access management page for RecordingStudioAccessible"

      class_option :mount_path, type: :string, default: "/recording_studio_accessible",
                                desc: "Route prefix used when mounting the engine"
      class_option :link_helper, type: :boolean, default: false,
                            desc: "Generate a host helper for linking recordable pages to the access management route"

      def mount_engine
        return if engine_mount_present?

        route %(mount RecordingStudioAccessible::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        return if File.exist?(destination_file(initializer_path))

        template "recording_studio_accessible_initializer.rb", initializer_path
      end

      def copy_helper
        return unless options[:link_helper]
        return if File.exist?(destination_file(helper_path))

        template "access_management_helper.rb", helper_path
      end

      def show_readme
        readme "ACCESS_MANAGEMENT.md" if behavior == :invoke
      end

      private

      def initializer_path
        "config/initializers/recording_studio_accessible.rb"
      end

      def helper_path
        "app/helpers/recording_studio_accessible/access_management_helper.rb"
      end

      def engine_mount_present?
        routes_file = destination_file("config/routes.rb")
        return false unless File.exist?(routes_file)

        File.read(routes_file).include?("mount RecordingStudioAccessible::Engine")
      end

      def destination_file(relative_path)
        File.join(destination_root, relative_path)
      end
    end
  end
end