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
  sh "mkdir -p pkg"
  sh "gem build stacks.gemspec"
  sh "mv stacks*.gem pkg"
  sh "cd pkg; fpm stacks-0.0.0.gem -s gem -t deb"
end
