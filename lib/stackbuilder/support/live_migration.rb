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

  def move_all()
    move_machines(@source_host.allocated_machines.map { |m| @factory.inventory.find_by_hostname(m[:fabric], m[:hostname]) })
  end

  private

  def move_machines(machines)
    check_results = @factory.compute_node_client.check_vm_definitions(@source_host.fqdn, machines.map(&:to_spec))

    bail "Did not receive check result from host" unless check_results.size == 1
    successful_vms = check_results.first[1].reject { |_, vm_result| vm_result[0] != 'success' }.keys
    failed_vms = machines.map(&:hostname) - successful_vms

    bail "Some VMs do not have up-to-date definitions and need re-provisioning: #{failed_vms.join(', ')}" unless failed_vms.empty?

    # TODO: check capacity for all proposed VMs across the rest of the fabric before continuing

    logger(Logger::INFO) { "Will perform live VM migration of these VMs: #{successful_vms.join(', ')}" }

    machines.each { |machine| perform_live_migration(machine) }
  end

  def perform_live_migration(machine)
    logger(Logger::INFO) { "Performing live VM migration of #{machine.hostname}" }

    new_host = "la-la-land"
    logger(Logger::INFO) { "#{machine.hostname} will be allocated to #{new_host}" }

    # invoke live migration
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end

end
