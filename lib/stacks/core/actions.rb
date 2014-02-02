require 'stacks/core/namespace'

module Stacks::Core::Actions
  attr_accessor :actions
  def self.extended(object)
    object.actions = {}

    object.action 'allocate' do |services, machine_def|
      machines = machine_def.flatten
      machine_specs = machine_def.flatten.map {|machine| machine.to_spec}
      fabrics = machines.map {|machine| machine.fabric}.uniq
      raise "we don't support launching in multiple locations right now" unless fabrics.size==1

      hosts = services.host_repo.find_current(fabrics.shift)

      hosts.allocated_machines(machine_specs).map do |machine, host|
        services.logger.info("#{machine[:qualified_hostnames][:mgmt]} already allocated to #{host.fqdn}")
      end

      hosts.allocate(machine_specs)

      hosts.new_machine_allocation.each do |machine, host|
        services.logger.info "#{machine[:qualified_hostnames][:mgmt]} *would be* allocated to #{host.fqdn}\n"
      end

   end

    object.action 'launch' do |services, machine_def|
      machines = machine_def.flatten
      machine_specs = machine_def.flatten.map {|machine| machine.to_spec}

      machines.each do |machine|
        if machine.hostname.include? 'OWNER-FACT-NOT-FOUND'
          raise "cannot instantiate machines in local site without owner fact"
        end
      end

      fabrics = machines.map {|machine| machine.fabric}.uniq
      raise "we don't support launching in multiple locations right now" unless fabrics.size==1

      hosts = services.host_repo.find_current(fabrics.shift)

      hosts.allocated_machines(machine_specs).map do |machine, host|
        services.logger.info("#{machine[:qualified_hostnames][:mgmt]} already allocated to #{host.fqdn}")
      end

      hosts.allocate(machine_specs)

      hosts.new_machine_allocation.each do |machine, host|
        services.logger.info "#{machine[:qualified_hostnames][:mgmt]} *now* allocated to #{host.fqdn}\n"
      end

      specs = hosts.to_unlaunched_specs()

      services.compute_controller.launch_raw(specs) do
        on :allocated do |vm, host|
          services.logger.info "#{vm} allocated to #{host}"
        end
        on :success do |vm, msg|
          services.logger.info "#{vm} launched successfully"
        end
        on :failure do |vm, msg|
          services.logger.error "#{vm} failed to launch: #{msg}"
        end
        on :unaccounted do |vm|
          services.logger.error "#{vm} was unaccounted for"
        end
        has :failure do
          raise "some machines failed to launch"
        end
      end
    end
  end

  def self.included(object)
    self.extended(object)
  end

  def action(name, &block)
    @actions[name] = block
  end

  def get_action(name)
    @actions[name]
  end
end
