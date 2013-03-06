require 'stacks/environment'
require 'puppet/node'
require 'puppet/indirector/plain'
class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize
    @stacks_inventory = Object.new
    @stacks_inventory.extend Stacks::DSL
    dirs = ['.','/etc/stacks/']
    dirs.each do |dir|
      file = "#{dir}/stack.rb"
      if File.exist? file
        config = IO.read file
        @stacks_inventory.instance_eval(config, file)
      end
    end
  end

  def find(request)
    node = super
    node.fact_merge
    machine = @stacks_inventory.find node.parameters['fqdn']
    unless machine.nil?
      node.classes = machine.to_enc
    end
    node
  end
end
