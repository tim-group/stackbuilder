require 'stacks/core/namespace'

module Stacks::Core::Actions
  attr_accessor :actions
  def self.extended(object)
    object.actions = {}

    object.action 'launch' do |services, machine_def|
      #TODO FIXME
      logger = Logger.new(STDOUT)
      print "FIXME - use the main logger - get here"
      machines = machine_def.flatten

      fabrics = machines.map {|machine| machine.fabric}.uniq
      raise "we don't support launching in multiple locations right now" unless fabrics.size==1

      hosts = services.host_repo.find_current(fabrics.shift)

      hosts.allocated_machines(machine_def.flatten).map do |machine, host|
        logger.info("#{machine.mgmt_fqdn} already allocated to #{host.fqdn}")
      end

      hosts.allocate(machine_def.flatten)

      hosts.new_machine_allocation.each do |machine, host|
        logger.info "#{machine.mgmt_fqdn} *now* allocated to #{host.fqdn}\n"
      end

      specs = hosts.to_unlaunched_specs()

      services.compute_controller.launch_raw(specs) do
        on :allocated do |vm, host|
          logger.info "#{vm} allocated to #{host}"
        end
        on :success do |vm, msg|
          logger.info "#{vm} launched successfully"
        end
        on :failure do |vm, msg|
          logger.error "#{vm} failed to launch: #{msg}"
        end
        on :unaccounted do |vm|
          logger.error "#{vm} was unaccounted for"
        end
        has :failure do
          fail "some machines failed to launch"
        end
      end
    end
  end

  def self.included(object)
    self.extended(object)
  end

  def action(name, &block)
    @actions = {name=> block}
  end

  def get_action(name)
    @actions[name]
  end
end