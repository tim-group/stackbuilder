require 'pp'
require 'rubygems'
require 'stacks/environment'

module Stacks
  module MCollective
    module Support
      attr_accessor :scope
 
      class MCollectiveRunner
        def run_puppet
        end
      end

      def mcollective_local(&block)
        return MCollectiveRunner.new
      end

      def mcollective_fabric(&block)
      end
    end
  end
end

include Rake::DSL
extend Stacks
include Stacks::MCollective::Support
Dir[".stacks/*.rb"].each {|file| require file}

namespace :sb do
  environments.each  do |env_name, env|
    namespace env_name.to_sym do
    env.generate
    scope=env

    namespace :machine do
      env.collapse_registries.each do |machine_name,machine_object|
        namespace machine_name.to_sym do
          desc "provision"
          task :provision do
            mcollective_fabric do
              provision_vm machine_object.to_enc
            end
          end

          desc "test"
          task :test do
            require 'rspec'
            pids = []
            RSpec::Core::Runner.disable_autorun!
	    config = RSpec.configuration
	    config.color_enabled = true
#	    documentation_formatter = config.send(:built_in_formatter, :documentation).new(config.output)
#	    reporter =  RSpec::Core::Reporter.new(documentation_formatter)

 #           config.instance_variable_set(:@reporter, reporter)

            4.times do
              pids << fork do 
                RSpec::Core::Runner.run(['spec.rb'], $stderr, $stdout)
              end
            end
            pids.each do |pid| waitpid(pid) end
            puts "\n\n"
          end
          desc "run_puppet"
          task :run_puppet do
            mcollective_local.run_puppet
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
