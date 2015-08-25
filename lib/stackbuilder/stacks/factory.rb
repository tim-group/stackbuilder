require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/mcollective_puppet'
require 'stackbuilder/compute/controller'
require 'stackbuilder/allocator/host_repository'
require 'stackbuilder/allocator/host_preference'
require 'stackbuilder/allocator/host_policies'
require 'stackbuilder/allocator/ephemeral_allocator'
require 'stackbuilder/dns/basic_dns_service'
require 'stackbuilder/stacks/core/services'
require 'stackbuilder/stacks/namespace'

class Stacks::Factory
  def inventory
    @inventory ||= Stacks::Inventory.new(defined?($options[:path]) ? $options[:path] : '.')
  end

  def policies
    @policies ||= [
      StackBuilder::Allocator::HostPolicies.ensure_mount_points_have_specified_storage_types_policy,
      StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy,
      StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy,
      StackBuilder::Allocator::HostPolicies.ha_group,
      StackBuilder::Allocator::HostPolicies.do_not_overallocate_ram_policy,
      StackBuilder::Allocator::HostPolicies.allocation_temporarily_disabled_policy,
      StackBuilder::Allocator::HostPolicies.require_persistent_storage_to_exist_policy
    ]
  end

  def preference_functions
    @preference_functions ||= [
      StackBuilder::Allocator::HostPreference.prefer_no_data,
      StackBuilder::Allocator::HostPreference.fewest_machines,
      StackBuilder::Allocator::HostPreference.alphabetical_fqdn
    ]
  end

  def compute_controller
    @compute_controller ||= Compute::Controller.new
  end

  def compute_node_client
    @compute_node_client ||= Compute::Client.new
  end

  def dns_service
    @dns_service ||= StackBuilder::DNS::BasicDNSService.new
  end

  def host_repository
    @host_repository ||= StackBuilder::Allocator::HostRepository.new(
      :machine_repo         => inventory,
      :preference_functions => preference_functions,
      :policies             => policies,
      :compute_node_client  => compute_node_client
    )
  end

  def allocator
    StackBuilder::Allocator::EphemeralAllocator.new(:host_repository => host_repository)
  end

  def services
    @services ||= Stacks::Core::Services.new(
      :compute_controller => compute_controller,
      :allocator          => allocator,
      :dns_service        => dns_service
    )
  end
end
