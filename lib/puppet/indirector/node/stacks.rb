require 'stacks/environment'
require 'puppet/node'
require 'puppet/indirector/plain'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def find(request)
    extend Stacks
    node = super
    node.fact_merge

    env = env "dev" do
      stack "ref" do
        loadbalancer "lb"
        virtualservice "refapp"
      end
    end

    env.generate()
    member = env.collapse_registries[node.parameters['hostname']]

    unless  member.nil?
      node.classes = member.to_enc[:enc][:classes]
    end

    node
  end
end
