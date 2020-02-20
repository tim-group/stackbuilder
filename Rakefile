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

namespace :docker do
  $region = 'eu-west-2'
  $repo = 'timgroup/stacks'

  def ecr_url
    account_id = %x{aws sts get-caller-identity --query Account --output text}.chomp
    "#{account_id}.dkr.ecr.#{$region}.amazonaws.com"
  end

  def image
    "#{ecr_url}/#{$repo}"
  end

  def tag_image(version, tag)
    manifest = %x{aws ecr batch-get-image --region #{$region} --repository-name #{$repo} --image-ids imageTag=#{version} --query 'images[].imageManifest' --output text}.chomp
    sh "aws ecr put-image --region #{$region} --repository-name #{$repo} --image-tag #{tag} --image-manifest '#{manifest}'"
  end

  desc 'Login to the docker repository'
  task :login do
    sh "aws ecr get-login-password --region #{$region} | docker login --username AWS --password-stdin #{ecr_url}"
  end

  desc 'Build the docker image'
  task :build do
    docker_version = `docker version --format "{{ .Client.Version }}"`.tr('^0-9.', '')
    if Gem::Version.new(docker_version) >= Gem::Version.new('18.09')
      ENV['DOCKER_BUILDKIT'] = '1'
    end
    sh "docker build --network host --build-arg version=#{version} -t stacks:#{version} ."
  end

  desc 'Tag and publish an unstable image'
  task :publish_unstable => [:login] do
    sh "docker tag stacks:#{version} #{image}:#{version}"
    sh "docker push #{image}:#{version}"

    tag_image(version, 'unstable')
  end

  desc 'Promote and publish an image to stable'
  task :promote_stable => [:login] do
    tag_image(version, 'stable')
  end
end
