require 'stacks/core/namespace'

##- allocate
##- allocate_ips
##-
##- launch

module Stacks::Core::Actions
  attr_accessor :actions
  def self.extended(object)
    object.actions = {}

    object.action 'allocate' do |services, machine_def|
      machines = machine_def.flatten
      machine_specs = machine_def.flatten.map { |machine| machine.to_spec }
      allocation_results = services.allocator.allocate(machine_specs)

      allocation_results[:already_allocated].each do |machine, host|
        services.logger.info("#{machine[:qualified_hostnames][:mgmt]} already allocated to #{host}")
      end

      allocation_results[:newly_allocated].each do |host, machines|
        machines.each do |machine|
          services.logger.info "#{machine[:qualified_hostnames][:mgmt]} *would be* allocated to #{host}\n"
        end
      end

    end

    object.action 'launch' do |services, machine_def|
      machines = machine_def.flatten
      machine_specs = machine_def.flatten.map { |machine| machine.to_spec }
      machines.each do |machine|
        if machine.hostname.include? 'OWNER-FACT-NOT-FOUND'
          raise "cannot instantiate machines in local site without owner fact"
        end
      end

      allocation_results = services.allocator.allocate(machine_specs)

      allocation_results[:already_allocated].each do |machine, host|
        services.logger.info("#{machine[:qualified_hostnames][:mgmt]} already allocated to #{host}")
      end

      allocation_results[:newly_allocated].each do |host, machines|
        machines.each do |machine|
          services.logger.info "#{machine[:qualified_hostnames][:mgmt]} *would be* allocated to #{host}\n"
        end
      end

      services.compute_controller.launch_raw(allocation_results[:newly_allocated]) do
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
        has :unaccounted do
          raise "some machines were unaccounted for"
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
