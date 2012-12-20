require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::LoadBalancer < Stacks::MachineDef
  def initialize(hostname, environment)
    super(hostname,environment)
  end

  def to_spec
    spec = super
    spec[:enc]={
      :classes=>{
        "base"=>nil,
        "loadbalancer"=>nil
      }
    }
    return spec
  end
end
