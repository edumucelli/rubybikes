# frozen_string_literal: true

require 'rubygems/package'
require 'tmpdir'
require 'open3'
require 'rbconfig'

artifact = Dir['pkg/rubybikes-*.gem'].max_by { |file| File.mtime(file) }
abort 'Build the gem before running package checks' unless artifact
spec = Gem::Package.new(artifact).spec
abort 'Recovery codes must never be packaged' if spec.files.any? { |file| file.include?('recovery-codes') }
abort 'Python files must never be packaged' if spec.files.any? { |file| file.end_with?('.py', '.pyc') || file.include?('requirements-engine') }
%w[lib/rubybikes/version.rb data/providers.json data/upstream.json sig/rubybikes.rbs LICENSE NOTICE].each do |file|
  abort "Package missing #{file}" unless spec.files.include?(file)
end
Dir.mktmpdir('rubybikes-package') do |directory|
  success = system(RbConfig.ruby, '-S', 'gem', 'install', File.expand_path(artifact), '--local', '--ignore-dependencies', '--no-document', '--install-dir', directory)
  abort 'Packaged gem installation failed' unless success
  env = { 'GEM_HOME' => directory, 'GEM_PATH' => ([directory] + Gem.path).join(File::PATH_SEPARATOR), 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil }
  code = <<~CHECK
    require 'rubybikes'
    unless Gem.loaded_specs.fetch('rubybikes').full_gem_path.start_with?(Dir.pwd)
      abort 'Loaded source checkout instead of packaged gem'
    end
    RubyBikes.open do |bikes|
      unless bikes.tags.size == 815 && bikes.providers.size == 85 && bikes.engine_info['implementation'] == 'ruby'
        abort 'Catalog mismatch'
      end
    end
    puts RubyBikes::VERSION
  CHECK
  output, status = Open3.capture2e(env, RbConfig.ruby, '-e', code, chdir: directory)
  abort "Installed gem smoke test failed: #{output}" unless status.success?
  puts "Verified installed RubyBikes #{output.strip}"
end
