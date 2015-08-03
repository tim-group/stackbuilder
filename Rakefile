require 'ci/reporter/rake/rspec'
require 'rspec/core/rake_task'

desc "Generate CTags"
task :ctags do
  sh "ctags -R --exclude=.git --exclude=build ."
end

desc "Run specs"
if ENV['STACKS_RSPEC_SEPARATE'] # run each rspec in a separate ruby instance
  require './spec/rake_override'
  SingleTestFilePerInterpreterSpec::RakeTask.new(:spec => ["ci:setup:rspec"]) do
    ENV['INSIDE_RSPEC'] = 'true'
  end
else # fast run (common ruby process for all tests)
  RSpec::Core::RakeTask.new(:spec => ["ci:setup:rspec"]) do
    ENV['INSIDE_RSPEC'] = 'true'
  end
end

desc 'Clean up the build directory'
task :clean do
  sh 'rm -rf build/'
end

desc "Create a debian package"
task :package do
  version = "0.0.#{ENV['BUILD_NUMBER']}"

  sh 'rm -rf build/package'
  sh 'mkdir -p build/package/usr/local/lib/site_ruby/timgroup/'
  sh 'cp -r lib/* build/package/usr/local/lib/site_ruby/timgroup/'
  sh 'mkdir -p build/package/usr/lib/ruby/vendor_ruby/puppet/indirector/node/'
  sh 'cp lib/puppet/indirector/node/stacks.rb build/package/usr/lib/ruby/vendor_ruby/puppet/indirector/node/'

  sh 'mkdir -p build/package/usr/local/bin/'
  sh 'cp -r bin/* build/package/usr/local/bin/'

  arguments = [
    '--description', 'stackbuilder',
    '--url', 'https://github.com/tim-group/stackbuilder',
    '-p', "build/stackbuilder-transition_#{version}.deb",
    '-n', 'stackbuilder-transition',
    '-v', "#{version}",
    '-m', 'Infrastructure <infra@timgroup.com>',
    '-d', 'ruby-bundle',
    '-a', 'all',
    '-t', 'deb',
    '-s', 'dir',
    '-C', 'build/package'
  ]

  argv = arguments.map { |x| "'#{x}'" }.join(' ')
  sh 'rm -f build/*.deb'
  sh "fpm #{argv}"
end

desc "Create a debian package"
task :install => [:package] do
  sh "sudo dpkg -i *.deb"
  sh "sudo /etc/init.d/mcollective restart;"
end

# needs to be run with sudo
# XXX used by jenkins. ci has sudo access but only for the 'rake' command
desc "Prepare for an omnibus run"
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

desc 'Run lint (Rubocop)'
task :lint do
  sh 'rubocop'
end
