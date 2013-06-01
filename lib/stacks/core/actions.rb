require 'stacks/core/namespace'

module Stacks::Actions
  attr_accessor :actions
  def self.extended(object)
    object.actions = {}

    object.action 'launch' do |services, machine_def|
      machines = machine_def.flatten

      fabrics = machines.map {|machine| machine.fabric}.uniq
      raise "we don't support launching in multiple locations right now" unless fabrics.size==1

      hosts = services.host_repo.find_current(fabrics.shift)
      hosts.allocate(machine_def.flatten)
      specs = hosts.to_unlaunched_specs()
      services.compute_controller.launch(specs)
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