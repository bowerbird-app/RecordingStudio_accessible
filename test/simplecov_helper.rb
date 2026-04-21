# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
end
