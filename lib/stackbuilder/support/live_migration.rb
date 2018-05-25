require 'stackbuilder/support/namespace'

class Support::LiveMigrator
  def initialize(factory, core_actions, source_host)
    @factory = factory
    @core_actions = core_actions
    @source_host = source_host
  end

  def move(machine)
    move_machines([machine])
  end

  def move_all
    move_machines(@source_host.allocated_machines.map { |m| @factory.inventory.find_by_hostname(m[:fabric], m[:hostname]) })
  end

  private

  def move_machines(machines)
    check_results = @factory.compute_node_client.check_vm_definitions(@source_host.fqdn, machines.map(&:to_spec))

    bail "Did not receive check result from host" unless check_results.size == 1
    successful_vm_names = check_results.first[1].reject { |_, vm_result| vm_result[0] != 'success' }.keys

    failed_vm_names = machines.map(&:hostname) - successful_vm_names
    bail "Some VMs have out-of-date definitions and need re-provisioning: #{failed_vm_names.join(', ')}" unless failed_vm_names.empty?

    logger(Logger::INFO) { "Will perform live VM migration of these VMs: #{successful_vm_names.join(', ')}" }

    safe_machines = machines.select { |machine| successful_vm_names.include?(machine.hostname) }
    safe_machine_specs = safe_machines.map(&:to_spec)

    preliminary_allocation = allocate_elsewhere(safe_machine_specs)
    preliminary_allocation.each do |host, allocated_machines|
      allocated_machines.each do |machine|
        logger(Logger::DEBUG) { "#{machine[:qualified_hostnames][:mgmt]} can be moved from #{@source_host.fqdn} to #{host}" }
      end
    end

    safe_machines.each { |machine| perform_live_migration(machine) }
  end

  def perform_live_migration(machine)
    logger(Logger::INFO) { "Performing live VM migration of #{machine.hostname}" }

    new_allocation = allocate_elsewhere([machine.to_spec])
    new_allocation.each do |host, machines|
      machines.each do |m|
        logger(Logger::INFO) { "#{m[:qualified_hostnames][:mgmt]} will be moved from #{@source_host.fqdn} to #{host}" }
      end
    end

    # invoke live migration
  end

  def allocate_elsewhere(specs)
    allocation_results = @factory.services.allocator.allocate(specs, [@source_host])

    allocation_results[:already_allocated].each do |machine, host|
      logger(Logger::ERROR) { "#{machine[:qualified_hostnames][:mgmt]} already allocated to #{host}" }
    end
    bail "VMs are already allocated elsewhere!?" unless allocation_results[:already_allocated].empty?

    allocation_results[:newly_allocated]
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
