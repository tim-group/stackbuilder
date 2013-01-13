require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/mcollective/support'
require 'ci/reporter/rspec'
require 'set'

include Rake::DSL
extend Stacks
include Stacks::MCollective::Support


Dir[".stacks/*.rb"].each {|file| require file}

def nslookup(host)
  return `dig #{host} @192.168.5.1 +short`.chomp
end

require 'rspec'
load 'system/machine/nrpe_spec.rb'
load 'system/virtualservice/end2end.rb'

module RSpecTests
  def self.extended(object)
    RSpec::Core::Runner.disable_autorun!
    config = RSpec.configuration
    config.color_enabled = true

    RSpec.configure do |c|
      c.alias_it_should_behave_like_to :hasbehavior, ''
    end
  end

  def rspec
    namespace self.name.to_sym do
      desc "launch the machines in this bucket"
      task :test do
        directory 'build'
        define_rspec()
        ENV['CI_REPORTS'] = 'build/spec/reports/'
        RSpec::Core::Runner.run(
          ['--format','CI::Reporter::RSpec'],
          $stderr,
          $stdout)
      end

      self.children.each do |child|
        child.rspec
      end
    end
  end

  def define_rspec
    self.children.each do |child|
      child.define_rspec
    end
    tests = self.rspecs
    describe "#{self.clazz}.#{self.name}." do
      tests.each do |test|
        hasbehavior test, self
      end
    end
  end
end



module RakeTasks
  def rake
    namespace self.name.to_sym do
      desc "launch the machines in this bucket"
      task :launch do
        pp self.machines
      end

      self.children.each do |child|
        child.rake
      end
    end
  end
end


namespace :sbx do
  environments.each do |env_name, env|
    env.recursive_extend(RakeTasks)
    env.recursive_extend(RSpecTests)
    env.rake
    env.rspec
  end
end

if false

  namespace :sb do
    environments.each  do |env_name, env|
      namespace env_name.to_sym do
        env.generate
        scope=env

        namespace :machine do
          env.collapse_registries.each do |machine_name,machine_object|
            namespace machine_name.to_sym do
              desc "show the spec yaml to send the compute controller"
              task :show_spec do
                puts [machine_object.to_spec].to_yaml
              end

              desc "build_vm"
              task :build do
                mcollective_fabric do
                  result = provision_vms([machine_object.to_spec])
                  pp result[0][:data]
                end
              end

              desc "wait for ping"
              task :wait_for_ping do
                mcollective_fabric(:broker=>nslookup("dev-puppetmaster-001.dev.net.local"),:key=>"seed") do
                  result = wait_for_ping([machine_object.fqdn])
                  pp result
                end
              end

              desc "puppet"
              task :puppet do
                mcollective_fabric(:broker=>nslookup("dev-puppetmaster-001.dev.net.local"),:key=>"seed") do
                  run_puppetroll([machine_object.fqdn])
                end

                mcollective_fabric(:broker=>nslookup("dev-puppetmaster-001.dev.net.local"),:key=>"seed") do
                  puppetca_sign(machine_object.fqdn)
                end

                mcollective_fabric(:broker=>nslookup("dev-puppetmaster-001.dev.net.local"),:key=>"seed") do
                  run_puppetroll([machine_object.fqdn])
                end
              end

              desc "provision"
              task :provision => ['wait_for_ping','puppet']

              desc "test"
              task :test do
                require 'rspec'
                pids = []
                RSpec::Core::Runner.disable_autorun!
                config = RSpec.configuration
                config.color_enabled = true
                RSpec::Core::Runner.run(
                  ['--format','CI::Reporter::RSpec', 'spec.rb'],
                  $stderr,
                  $stdout)
                  pids.each do |pid| waitpid(pid) end
                  puts "\n\n"
              end
            end
          end
        end

        namespace :stack do
          env.stacks.each do |stack,stack_object|
            namespace stack.to_sym do
              desc "provision"
              task :provision do
              end

              desc "test"
              task :test do
              end

              desc "run_puppet"
              task :run_puppet do
              end
            end
          end
        end

        namespace :list do
          desc "list stacks"
          task :stacks do
            pp env.stacks
          end

          desc "list stacks"
          task :virtualservices do
          end

          desc "list stacks"
          task :machines do
            pp env.collapse_registries
          end
        end
      end
    end

    desc "list environments"
    task :environments do
      pp environments.keys
    end

  end
end
