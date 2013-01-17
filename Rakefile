require 'rubygems'
require 'rake/dsl_definition'
require 'rake'
require 'rspec/core/rake_task'

desc "Run specs"
RSpec::Core::RakeTask.new() do |t|
  t.rspec_opts = %w[--color]
  t.pattern = "spec/**/*_spec.rb"
end

desc "Create a debian package"
task :package do
  sh "mkdir -p build"
  sh "if [ -f *.gem ]; then rm *.gem; fi"
  sh "gem build stacks.gemspec && mv stacks-*.gem build/"
  sh "cd build && fpm -s gem -t deb -n stacks stacks-*.gem"
end
