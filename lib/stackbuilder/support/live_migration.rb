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
    move_machines(@source_host.allocated_machines.map { |m| @factory.inventory.find_by_hostname(m[:fabric], m[:hostname]) })
  end

  private

  def move_machines(machines, best_effort = false)
    check_results = @factory.compute_node_client.check_vm_definitions(@source_host.fqdn, machines.map(&:to_spec))

    bail "Did not receive check result from host" unless check_results.size == 1
    successful_vm_names = check_results.first[1].reject { |_, vm_result| vm_result[0] != 'success' }.keys

    failed_vm_names = machines.map(&:hostname) - successful_vm_names
    unless failed_vm_names.empty?
      level = best_effort ? Logger::WARN : Logger::FATAL
      logger(level) { "Some VMs have out-of-date definitions and need re-provisioning: #{failed_vm_names.join(', ')}" }
      exit 1 unless best_effort
    end

    logger(Logger::INFO) { "Will reallocate these VMs: #{successful_vm_names.join(', ')}" }

    safe_machines = machines.select { |machine| successful_vm_names.include?(machine.hostname) }

    preliminary_allocation = allocate_elsewhere(safe_machines.map(&:to_spec), best_effort)
    preliminary_allocation[:failed_to_allocate].each do |spec, reason|
      logger(Logger::WARN) { "#{spec[:qualified_hostnames][:mgmt]} can't be moved from #{@source_host.fqdn} due to lack of capacity" }
      logger(Logger::DEBUG) { reason }
    end

    preliminary_allocation[:newly_allocated].each do |host, allocated_specs|
      allocated_specs.each do |spec|
        logger(Logger::DEBUG) { "#{spec[:qualified_hostnames][:mgmt]} can be moved from #{@source_host.fqdn} to #{host}" }
      end
    end

    machine_specs_that_fit = preliminary_allocation[:newly_allocated].values.flatten
    logger(Logger::INFO) { "Will perform live VM migration of these VMs: #{machine_specs_that_fit.map { |s| s[:hostname] }.join(', ')}" }
    machine_specs_that_fit.each { |spec| perform_live_migration(spec) }
  end

  def perform_live_migration(spec)
    logger(Logger::INFO) { "Performing live VM migration of #{spec[:hostname]}" }

    allocation_results = allocate_elsewhere([spec], false)
    dest_host_fqdn = allocation_results[:newly_allocated].keys.first

    logger(Logger::INFO) { "#{spec[:qualified_hostnames][:mgmt]} will be moved from #{@source_host.fqdn} to #{dest_host_fqdn}" }

    # invoke live migration
  end

  def allocate_elsewhere(specs, best_effort)
    allocation_results = @factory.services.allocator.allocate(specs, [@source_host], best_effort)

    allocation_results[:already_allocated].each do |spec, host|
      logger(Logger::ERROR) { "#{spec[:qualified_hostnames][:mgmt]} already allocated to #{host}" }
    end
    bail "VMs are already allocated elsewhere!?" unless allocation_results[:already_allocated].empty?

    allocation_results
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
