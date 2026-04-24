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

      def copy_mailer_templates
        copy_mailer_template("access_granted.html.erb")
        copy_mailer_template("access_granted.text.erb")
      end

      def add_yaml_config
        unless yes?("Would you like to add `config/recording_studio_accessible.yml` for environment-specific settings? [y/N]")
          return
        end

        template "recording_studio_accessible.yml", "config/recording_studio_accessible.yml"
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end

      private

      def copy_mailer_template(template_name)
        target_path = File.join("app/views/recording_studio_accessible/access_granted_mailer", template_name)
        return if File.exist?(File.join(destination_root, target_path))

        copy_file template_name, target_path
      end
    end
  end
end
