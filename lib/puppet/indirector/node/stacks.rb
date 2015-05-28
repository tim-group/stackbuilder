require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
require 'puppet/node'
require 'puppet/indirector/node/plain'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize(stacks_inventory = Stacks::Inventory.new('/etc/stacks'), delegate = Puppet::Node::Plain.new)
    @stacks_inventory = stacks_inventory
    @delegate = delegate
  end

  def find(request)
    node = @delegate.find(request)
    machine = @stacks_inventory.find(request.key)
    if machine
      classes = machine.to_enc
      node.classes = classes if classes
      node.parameters['logicalenv'] = machine.environment.name
    end
    node
  end
end
