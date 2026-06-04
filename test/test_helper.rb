# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "recording_studio_accessible"

unless Object.method_defined?(:stub)
  class Object
    def stub(method_name, value)
      singleton = singleton_class
      backup_method_name = :"__recording_studio_accessible_stubbed_#{method_name}"
      method_existed = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      singleton.alias_method(backup_method_name, method_name) if method_existed
      singleton.define_method(method_name) do |*args, **kwargs, &block|
        next value unless value.respond_to?(:call)

        kwargs.empty? ? value.call(*args, &block) : value.call(*args, **kwargs, &block)
      end

      yield self
    ensure
      singleton.remove_method(method_name) if singleton.method_defined?(method_name)
      if method_existed
        singleton.alias_method(method_name, backup_method_name)
        singleton.remove_method(backup_method_name)
      end
    end
  end
end
