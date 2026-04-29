# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  test_files = FileList["test/**/*_test.rb"]
  t.test_files = test_files.exclude(
    "test/dummy/**/*_test.rb",
    "test/integration/**/*_test.rb",
    "test/rename_verification_test.rb"
  )
  t.verbose = false
end

namespace :test do
  desc "Run rename verification tests to validate gem naming consistency"
  task :rename_verification do
    ruby "test/rename_verification_test.rb", verbose: true
  end

  desc "Run rename verification tests in verbose mode"
  task :rename_verification_verbose do
    ruby "test/rename_verification_test.rb", "--verbose", verbose: true
  end
end

namespace :dummy do
  desc "Run the dummy Rails app test suite"
  task :test do
    dummy_root = File.expand_path("test/dummy", __dir__)

    Dir.chdir(dummy_root) do
      Bundler.with_unbundled_env do
        sh "bin/rails test"
      end
    end
  end
end

desc "Run the root gem tests and the dummy Rails app suite"
task "app:test" => [:test, "dummy:test"]

task default: :test
