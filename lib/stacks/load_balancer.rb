require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::LoadBalancer < Stacks::MachineDef
  attr_reader :name
  def initialize(name)
    @name = name
  end

  def to_enc
    return {
      :enc=>{
        :classes=>{
          :base=>nil,
          :loadbalancer=>nil
        }
      }
    }
  end
end