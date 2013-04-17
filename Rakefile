require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'fileutils'
require 'rspec/core/rake_task'
require 'fpm'

desc "Run specs"
RSpec::Core::RakeTask.new() do |t|
  t.rspec_opts = %w[--color]
  t.pattern = "spec/**/*_spec.rb"
end

desc "Create a debian package"
task :package do
  sh "mkdir -p build"
  sh "if [ `ls -1 build/ | wc -l` != 0 ]; then rm -r build/*; fi"
  sh "if [ -f *.gem ]; then rm *.gem; fi"
  sh "gem build stacks.gemspec && mv stacks-*.gem build/"
  sh "cd build && fpm -s gem -t deb -n stacks stacks-*.gem"
end

desc "Create a debian package"
task :install => [:package] do
  sh "sudo dpkg -i build/*.deb"
  sh "sudo /etc/init.d/mcollective restart;"
end
