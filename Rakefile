require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'fileutils'
require 'rspec/core/rake_task'
require 'fpm'

desc "Generate CTags"
task :ctags do
  sh "ctags -R --exclude=.git --exclude=build ."
end

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
  t.rspec_opts = %w(--color)
  t.pattern = "spec/**/*_spec.rb"
end

desc "Create a debian package"
task :package do
  hash = `git rev-parse --short HEAD`.chomp
  v_part = ENV['BUILD_NUMBER'] || "0.pre.#{hash}"
  version = "0.0.#{v_part}"

  sh "rm -f *.deb *.gem"
  sh "rm -rf build/"

  # XXX compatible with both 1.8 and 1.9 during the transition period
  sh "mkdir -p build/usr/local/lib/site_ruby/1.8"
  sh "cp -r lib/* build/usr/local/lib/site_ruby/1.8"
  sh "mkdir -p build/usr/local/lib/site_ruby/1.9.1"
  sh "cp -r lib/* build/usr/local/lib/site_ruby/1.9.1"
  sh "mkdir -p build/usr/local/bin"
  sh "cp bin/* build/usr/local/bin"

  sh "fpm -s dir -t deb --architecture all -C build --name stacks "\
     "--version #{version} --deb-pre-depends rubygem-collimator"
end

desc "Create a debian package"
task :install => [:package] do
  sh "sudo dpkg -i *.deb"
  sh "sudo /etc/init.d/mcollective restart;"
end

desc "Run lint (Rubocop)"
task :lint do
  sh "/var/lib/gems/1.9.1/bin/rubocop --require rubocop/formatter/checkstyle_formatter "\
     "--format RuboCop::Formatter::CheckstyleFormatter --out tmp/checkstyle.xml"
end
