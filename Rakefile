# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << 'lib'
  task.pattern = 'test/native/test_*.rb'
end

desc 'Lint maintained Ruby sources and tests'
task :lint do
  sh 'bundle exec rubocop'
end

desc 'Check the shipped Ruby type signatures'
task :typecheck do
  sh 'bundle exec steep check'
end

task check: %i[test lint typecheck build]
task default: :test
