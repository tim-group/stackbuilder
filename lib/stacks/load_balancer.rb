require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::LoadBalancer < Stacks::MachineDef
  def initialize(hostname)
    super(hostname)
  end

  def configure(env)
    env.find_all(VirtualServer.class).each do |virtualserver|
      vip_name = virtualserver.vip_name
    end
  end

  def to_tree
    {}
  end

  def to_spec
    spec = super
    return spec
  end
end
