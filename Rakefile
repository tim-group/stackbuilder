# XXX remove all but the "rake_task" requires once ruby1.8 is abandoned
require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'fileutils'
require 'fpm'
require 'rspec/core/rake_task'

desc "Generate CTags"
task :ctags do
  sh "ctags -R --exclude=.git --exclude=build ."
end

desc "Run specs"
if ENV['STACKS_RSPEC_SEPARATE'] # run each rspec in a separate ruby instance
  require './spec/rake_override'
  SingleTestFilePerInterpreterSpec::RakeTask.new do
    ENV['INSIDE_RSPEC'] = 'true'
  end
else # fast run (common ruby process for all tests)
  RSpec::Core::RakeTask.new do
    ENV['INSIDE_RSPEC'] = 'true'
  end
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

# needs to be run with sudo
# XXX used by jenkins. ci has sudo access but only for the 'rake' command
desc "Prepare for an omnibus run "
task :omnibus_prep do
  sh "rm -rf /opt/stackbuilder" # XXX very bad
  sh "mkdir -p /opt/stackbuilder"
  sh "chown \$SUDO_UID:\$SUDO_GID /opt/stackbuilder"
end

desc "Prepare a directory tree for omnibus"
task :omnibus do
  sh "rm -rf build/omnibus"

  sh "mkdir -p build/omnibus"
  sh "mkdir -p build/omnibus/bin"
  sh "mkdir -p build/omnibus/lib/ruby/site_ruby"
  sh "mkdir -p build/omnibus/embedded/lib/ruby/site_ruby"

  sh "cp -r bin/* build/omnibus/bin"
  sh "cp -r lib/* build/omnibus/embedded/lib/ruby/site_ruby"
  # expose stackbuilder libs; required by stackbuilder-config
  sh "ln -s ../../../embedded/lib/ruby/site_ruby/stackbuilder build/omnibus/lib/ruby/site_ruby/stackbuilder"
  sh "ln -s ../../../embedded/lib/ruby/site_ruby/puppet build/omnibus/lib/ruby/site_ruby/puppet"
end

desc "Run lint (Rubocop)"
task :lint do
  sh "/var/lib/gems/1.9.1/bin/rubocop --require rubocop/formatter/checkstyle_formatter "\
     "--format RuboCop::Formatter::CheckstyleFormatter --out tmp/checkstyle.xml"
end
