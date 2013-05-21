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
  sh "if [ `ls -1 *.deb 2>/dev/null | wc -l` != 0 ]; then rm *.deb; fi"
  sh "if [ `ls -1 build/ 2>/dev/null | wc -l` != 0 ]; then rm -r build/*; fi"
  sh "if [ -f *.gem ]; then rm *.gem; fi"
  sh "mkdir -p build/usr/local/lib/site_ruby/1.8"
  sh "mkdir -p build/usr/local/bin"
  hash = `git rev-parse --short HEAD`.chomp
  v_part= ENV['BUILD_NUMBER'] || "0.pre.#{hash}"
  version = "0.0.#{v_part}"
  sh "cp bin/* build/usr/local/bin"
  sh "cp -r lib/* build/usr/local/lib/site_ruby/1.8"
  sh "fpm -s dir -t deb --architecture all -C build --name stacks --version #{version}"
end

desc "Create a debian package"
task :install => [:package] do
  sh "sudo dpkg -i *.deb"
  sh "sudo /etc/init.d/mcollective restart;"
end
