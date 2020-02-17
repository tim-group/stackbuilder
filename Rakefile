require 'ci/reporter/rake/rspec'
require 'rspec/core/rake_task'

def version
  v = ENV['BUILD_NUMBER'] || "0.#{`git rev-parse --short HEAD`.chomp.hex}"
  "0.0.#{v}"
end

desc 'Run specs'
RSpec::Core::RakeTask.new(:spec => ['ci:setup:rspec'])

desc 'Clean up the build directory'
task :clean do
  sh 'rm -rf build/'
end

desc 'Create a debian package'
task :package do
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
    '-p', "build/stackbuilder_#{version}.deb",
    '-n', 'stackbuilder',
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

desc 'Create a debian package'
task :install => [:package] do
  sh 'sudo dpkg -i build/*.deb'
  sh 'sudo /etc/init.d/mcollective restart;'
end

desc 'Generate CTags'
task :ctags do
  sh 'ctags -R --exclude=.git --exclude=build .'
end

desc 'Run lint (Rubocop)'
task :lint do
  sh 'rubocop bin lib spec'
end

desc 'Build the docker image'
task :build do
  docker_version = `docker version --format "{{ .Client.Version }}"`.tr('^0-9.', '')
  if Gem::Version.new(docker_version) >= Gem::Version.new('18.09')
    ENV['DOCKER_BUILDKIT'] = '1'
  end
  sh "docker build --network host -t stacks:#{version} ."
  sh "docker tag stacks:#{version} stacks:latest"
end
