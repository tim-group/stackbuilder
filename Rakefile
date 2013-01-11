require 'rubygems'
require 'rspec/core/rake_task'

import 'lib/stacks/rake/tasks.rb'


desc "Run specs"
RSpec::Core::RakeTask.new() do |t|
    t.rspec_opts = %w[--color]
    t.pattern = "spec/**/*_spec.rb"
end

desc "Create a debian package"
task :package do
  sh "mkdir -p pkg"
  sh "gem build stack_enc.gemspec"
  sh "mv stack_enc*.gem pkg"
  sh "cd pkg; fpm stack_enc-0.0.0.gem -s gem -t deb"
end
