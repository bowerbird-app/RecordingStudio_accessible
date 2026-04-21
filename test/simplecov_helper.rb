# frozen_string_literal: true

begin
  require "simplecov"
rescue LoadError
  nil
else
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/db/"
  end
end
