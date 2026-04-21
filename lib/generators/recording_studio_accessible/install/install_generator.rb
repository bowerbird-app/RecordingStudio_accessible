# frozen_string_literal: true

require "rails/generators"

module RecordingStudioAccessible
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioAccessible into your application"

      class_option :mount, type: :boolean, default: false,
                           desc: "Mount the optional addon status/demo engine"
      class_option :mount_path, type: :string, default: "/recording_studio_accessible",
                                desc: "Route prefix used when mounting the optional engine"

      def mount_engine
        return unless options[:mount]

        route %(mount RecordingStudioAccessible::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        template "recording_studio_accessible_initializer.rb", "config/initializers/recording_studio_accessible.rb"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/recording_studio_accessible.yml` for environment-specific settings? [y/N]")

        template "recording_studio_accessible.yml", "config/recording_studio_accessible.yml"
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
