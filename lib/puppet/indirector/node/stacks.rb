require 'stacks/environment'
require 'puppet/node'
require 'puppet/indirector/node/plain'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize(dir='/etc/stacks', delegate=Puppet::Node::Plain.new)
    file = "#{dir}/stack.rb"
    raise "no stacks.rb found in #{dir}" unless File.exist? file
    config = IO.read file
    @stacks_inventory = Object.new
    @stacks_inventory.extend Stacks::DSL
    @stacks_inventory.instance_eval(config, file)

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
