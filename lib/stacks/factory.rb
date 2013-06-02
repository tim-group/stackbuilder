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
require 'stacks/core/services'
require 'stacks/namespace'

class Stacks::Factory
  def inventory()
    @inventory ||= Stacks::Inventory.new('.')
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
      :compute_node_client => compute_node_client)
  end

  def services()
    @services ||= Stacks::Core::Services.new(
      :compute_controller=>compute_controller,
      :host_repo =>host_repository
    )
  end
end