require 'stacks/environment'
require 'puppet/node'
require 'puppet/indirector/plain'

class Puppet::Node::Stackbuilder < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def find(request)
    node = super
    node.fact_merge

    env = env "dev", :domain=>"dev.net.local" do
      virtualservice "refapp"
    end
    env.generate()
    member = env.collapse_registries[node.name]
    node.classes = member.to_enc[:enc][:classes]
    node
  end
end
