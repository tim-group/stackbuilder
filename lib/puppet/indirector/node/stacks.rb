require 'stacks/environment'
require 'puppet/node'
require 'puppet/indirector/plain'
class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize
    extend Stacks::DSL
    dirs = ['.','/etc/stacks/']
    dirs.each do |dir|
      file = "#{dir}/stack.rb"
      if File.exist? file
        config = IO.read '/home/dellis/workspace/refstack/stack.rb'
        instance_eval(config, '/home/dellis/workspace/refstack/stack.rb')
      end
    end
    bind
  end

  def find(request)
    node = super
    node.fact_merge
    node.classes = enc_for node.parameters[:fqdn]
    node
  end
end
