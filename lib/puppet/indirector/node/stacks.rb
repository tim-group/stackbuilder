require 'stacks/environment'
require 'stacks/inventory'
require 'puppet/node'
require 'puppet/indirector/node/plain'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize(stacks_inventory=Stacks::Inventory.new('/etc/stacks'), delegate=Puppet::Node::Plain.new)
    @stacks_inventory = stacks_inventory
    @delegate = delegate
  end

  def find(request)
    node = @delegate.find(request)
    classes = find_stack_classes(request.key)
    if classes
      node.classes = classes
    end
    return node
  end

  def find_stack_classes(fqdn)
    machine = @stacks_inventory.find(fqdn)
    return nil if machine.nil?
    return machine.to_enc
  end

end
