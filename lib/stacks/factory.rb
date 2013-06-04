require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/inventory'
require 'support/mcollective'
require 'support/mcollective_puppet'
require 'compute/controller'
require 'support/logger'
require 'stacks/hosts/host_repository'
require 'stacks/hosts/host_preference'
require 'stacks/hosts/host_policies'
require 'stacks/core/services'
require 'stacks/namespace'

class Stacks::Factory
  def logger()
    return @log unless @log.nil?

    @log = Logger.new STDOUT
    @log.instance_eval do
      @formatter = Support::RakeFormatter.new
      def start(task)
        @start_time = Time.now
        if @formatter.interactive?
          puts "\e[1m\e[34m:#{task}\e[0m"
        else
          puts ":#{task}"
        end
      end

      def failed(task)
        @elapsed = Time.now - @start_time
        if @formatter.interactive?
          puts "\n\e[1m\e[31m:#{task} failed in #{@elapsed}\e[0m\n"
        else
          puts "\n:#{task} failed in #{@elapsed}\n"
        end
      end

      def passed(task)
        @elapsed = Time.now - @start_time
        if @formatter.interactive?
          puts "\n\e[1m\e[32m:#{task} passed in #{@elapsed}s\e[0m\n"
        else
          puts "\n:#{task} passed in #{@elapsed}s\n"
        end
      end
    end
    @log
  end

  def inventory()
    @inventory ||= Stacks::Inventory.new('.')
  end

  def policies()
    @policies ||= [
#      Stacks::Hosts::HostPolicies.ha_group_policy
    ]
  end

  def preference_functions()
    @preference_functions ||= [
      Stacks::Hosts::HostPreference.least_machines(),
      Stacks::Hosts::HostPreference.alphabetical_fqdn()
    ]
  end

  def compute_controller()
    @compute_controller ||= Compute::Controller.new
  end

  def compute_node_client()
    @compute_node_client ||= Compute::Client.new()
  end

  def host_repository()
    @host_repository ||= Stacks::Hosts::HostRepository.new(
      :machine_repo => inventory,
      :preference_functions=>preference_functions,
      :policies => policies,
      :compute_node_client => compute_node_client)
  end

  def services()
    @services ||= Stacks::Core::Services.new(
      :compute_controller=>compute_controller,
      :host_repo =>host_repository,
      :logger => logger
    )
  end
end
