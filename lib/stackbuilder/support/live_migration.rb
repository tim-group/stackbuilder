require 'stackbuilder/support/namespace'

class Support::LiveMigrator
  def initialize(factory, source_host)
    @factory = factory
    @source_host = source_host
  end

  def move(machine)
    move_machines([machine])
  end

  def move_all
    move_machines(
      @source_host.allocated_machines.map { |m| @factory.inventory.find_by_hostname(m[:fabric], m[:hostname]) },
      ENV['BEST_EFFORT'] == 'true'
    )
  end

  private

  def move_machines(machines, best_effort = false)
    safe_machines = vms_that_are_safe_to_move(machines, best_effort)
    moveable_machines = vms_that_can_be_reallocated(safe_machines, best_effort)

    logger(Logger::INFO) { "Will perform live VM migration of these VMs: #{moveable_machines.map(&:hostname).join(', ')}" }
    moveable_machines.each { |machine| perform_live_migration(machine) }
  end

  def vms_that_are_safe_to_move(machines, best_effort)
    check_results = @factory.compute_node_client.check_vm_definitions(@source_host.fqdn, machines.map(&:to_spec))

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
    preliminary_allocation = allocate_elsewhere(machines.map { |m| m.to_spec(true) }, true)
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
    logger(Logger::INFO) { "Performing live VM migration of #{machine.hostname}" }

    spec = machine.to_spec(true)
    allocation_results = allocate_elsewhere([spec], false)
    dest_host_fqdn = allocation_results[:newly_allocated].keys.first
    source_host_fqdn = @source_host.fqdn

    logger(Logger::INFO) { "#{machine.mgmt_fqdn} will be moved from #{source_host_fqdn} to #{dest_host_fqdn}" }

    @factory.compute_node_client.enable_live_migration(source_host_fqdn, dest_host_fqdn)
    @factory.compute_node_client.create_storage(dest_host_fqdn, [spec])
    @factory.compute_node_client.live_migrate_vm(source_host_fqdn, dest_host_fqdn, machine.hostname)
    # check migrated vm
    # destroy old vm
    @factory.compute_node_client.disable_live_migration(source_host_fqdn, dest_host_fqdn)
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
