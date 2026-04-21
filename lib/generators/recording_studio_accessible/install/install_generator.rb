# frozen_string_literal: true

require "rails/generators"

module RecordingStudioAccessible
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioAccessible into your application"

      class_option(
        :mount_path,
        type: :string,
        default: "/recording_studio_accessible",
        desc: "Route prefix used when mounting the engine"
      )

      def mount_engine
        route %(mount RecordingStudioAccessible::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        template "recording_studio_accessible_initializer.rb", "config/initializers/recording_studio_accessible.rb"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/recording_studio_accessible.yml` for environment-specific settings? [y/N]")

        template "recording_studio_accessible.yml", "config/recording_studio_accessible.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")
        return show_missing_tailwind_notice unless File.exist?(tailwind_css_path)

        tailwind_content = File.read(tailwind_css_path)
        missing_lines = tailwind_source_lines.reject { |line| tailwind_content.include?(line) }

        if missing_lines.empty?
          say "Tailwind already configured to include RecordingStudioAccessible and FlatPack sources.", :green
          return
        end

        if tailwind_content.include?('@import "tailwindcss"')
          inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
            [
              "\n/* Include RecordingStudioAccessible engine views for Tailwind CSS */",
              missing_lines.first(2),
              "\n/* Include FlatPack component sources for Tailwind CSS */",
              missing_lines.drop(2)
            ].flatten.reject(&:empty?).join("\n") + "\n"
          end
          say "Added RecordingStudioAccessible and FlatPack sources to Tailwind CSS configuration.", :green
          return
        end

        say "Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow
        missing_lines.each { |line| say "  #{line}", :yellow }
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end

      private

      def show_missing_tailwind_notice
        say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
        tailwind_source_lines.each { |line| say "  #{line}", :yellow }
      end

      def tailwind_source_lines
        [
          '@source "../../vendor/bundle/**/recording_studio_accessible/app/views/**/*.erb";',
          '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/recording_studio_accessible-*/app/views/**/*.erb";',
          '@source "../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}";',
          '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";'
        ]
      end
    end
  end
end
