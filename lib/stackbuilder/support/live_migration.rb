require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_rpcutil'

class Support::LiveMigrator
  def initialize(factory, source_host, rpcutil = Support::MCollectiveRpcutil.new)
    @factory = factory
    @source_host = source_host
    @rpcutil = rpcutil
  end

  def move(machine, force = false)
    move_machines([machine], false, force)
  end

  def move_all(force = false)
    best_effort = ENV['BEST_EFFORT'] == 'true'

    machines_not_in_model, machines_in_model = @source_host.allocated_machines.partition { |m| m.include?(:in_model) && m[:in_model] == false }
    machines_not_in_model.map { |vm| vm[:hostname] }.each do |vm_name|
      logger(best_effort ? Logger::WARN : Logger::FATAL) { "#{vm_name} is not in the stacks model so cannot be live migrated." }
    end
    exit 1 unless machines_not_in_model.empty? || best_effort

    move_machines(
      machines_in_model.map { |m| @factory.inventory.find_by_hostname(m[:fabric], m[:hostname]) },
      best_effort,
      force
    )
  end

  private

  def move_machines(machines, best_effort = false, force = false)
    safe_machines = vms_that_are_safe_to_move(machines, best_effort, force)
    moveable_machines = vms_that_can_be_reallocated(safe_machines, best_effort)

    logger(Logger::INFO) { "Will perform live VM migration of these VMs: #{moveable_machines.map(&:hostname).join(', ')}" }
    moveable_machines.each { |machine| perform_live_migration(machine) }
  end

  def vms_that_are_safe_to_move(machines, best_effort, force)
    check_results = @factory.compute_node_client.check_vm_definitions(@source_host.fqdn, machines.map(&:to_spec), force)

    bail "Did not receive check result from host" unless check_results.size == 1
    successful_vm_names = check_results.first[1].select { |_, vm_result| vm_result[0] == 'success' }.keys

    failed_vm_names = machines.map(&:hostname) - successful_vm_names
    failed_vm_names.each do |vm_name|
      logger(best_effort ? Logger::WARN : Logger::FATAL) { "#{vm_name} has an out-of-date definition and must be re-provisioned." }
    end
    exit 1 unless failed_vm_names.empty? || (best_effort && !successful_vm_names.empty?)

    logger(Logger::INFO) { "These VMs are safe to migrate: #{successful_vm_names.join(', ')}" }
    machines.select { |machine| successful_vm_names.include?(machine.hostname) }
  end

  def vms_that_can_be_reallocated(machines, best_effort)
    preliminary_allocation = allocate_elsewhere(machines.map { |m| creatable_destroyable_spec_for(m) }, true)
    preliminary_allocation[:newly_allocated].each do |host, allocated_specs|
      allocated_specs.each do |spec|
        logger(Logger::DEBUG) { "#{spec[:qualified_hostnames][:mgmt]} can be moved from #{@source_host.fqdn} to #{host}" }
      end
    end
    preliminary_allocation[:failed_to_allocate].each do |spec, reason|
      level = best_effort ? Logger::WARN : Logger::FATAL
      logger(level) { "#{spec[:qualified_hostnames][:mgmt]} can't be moved from #{@source_host.fqdn} due to lack of capacity" }
      logger(best_effort ? Logger::DEBUG : Logger::ERROR) { reason }
    end
    exit 1 unless preliminary_allocation[:failed_to_allocate].empty? || (best_effort && !preliminary_allocation[:newly_allocated].empty?)

    allocated_vm_names = preliminary_allocation[:newly_allocated].values.flatten.map { |spec| spec[:hostname] }
    machines.select { |machine| allocated_vm_names.include?(machine.hostname) }
  end

  def allocate_elsewhere(specs, best_effort)
    allocation_results = @factory.services.allocator.allocate(specs, [@source_host], best_effort)

    allocation_results[:already_allocated].each do |spec, host|
      logger(Logger::ERROR) { "#{spec[:qualified_hostnames][:mgmt]} already allocated to #{host}" }
    end
    bail "VMs are already allocated elsewhere!?" unless allocation_results[:already_allocated].empty?

    allocation_results
  end

  def perform_live_migration(machine)
    vm_name = machine.hostname
    logger(Logger::INFO) { "Performing live VM migration of #{vm_name}" }

    spec = creatable_destroyable_spec_for(machine)
    allocation_results = allocate_elsewhere([spec], false)
    dest_host_fqdn = allocation_results[:newly_allocated].keys.first
    source_host_fqdn = @source_host.fqdn

    logger(Logger::INFO) { "#{vm_name} will be moved from #{source_host_fqdn} to #{dest_host_fqdn}" }

    begin
      @factory.compute_node_client.enable_live_migration(source_host_fqdn, dest_host_fqdn)

      logger(Logger::INFO) { "Creating storage for #{vm_name} on #{dest_host_fqdn}" }
      @factory.compute_node_client.create_storage(dest_host_fqdn, [spec])

      logger(Logger::INFO) { "Initiating migration of #{vm_name} on #{source_host_fqdn}" }
      @factory.compute_node_client.live_migrate_vm(source_host_fqdn, dest_host_fqdn, vm_name)

      host_results = @factory.compute_node_client.audit_hosts([source_host_fqdn, dest_host_fqdn], false, false, false)
      fail "#{vm_name} not active on destination host" unless host_results[dest_host_fqdn][:active_domains].include? vm_name
      fail "#{vm_name} not inactive on source host" unless host_results[source_host_fqdn][:inactive_domains].include? vm_name
      fail "#{vm_name} did not respond to mco ping" if @rpcutil.ping(machine.mgmt_fqdn).nil?

      logger(Logger::INFO) { "Live migration of #{vm_name} successful, cleaning up old instance on #{source_host_fqdn}" }
      @factory.compute_node_client.clean_post_migration(source_host_fqdn, spec)
      logger(Logger::INFO) { "Cleanup completed" }
    ensure
      @factory.compute_node_client.disable_live_migration(source_host_fqdn, dest_host_fqdn)
    end
  end

  def creatable_destroyable_spec_for(machine_def)
    spec = machine_def.to_spec
    spec[:storage] = machine_def.turn_on_persistent_storage_creation(spec[:storage])
    spec[:disallow_destroy] = false
    spec
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
