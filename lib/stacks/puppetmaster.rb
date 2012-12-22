require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::PuppetMaster < Stacks::MachineDef
  def initialize(hostname, environment)
    super(hostname,environment)
  end

  def to_spec
    spec = super
    spec[:enc] = {
      "classes"=>{
        "rabbitmq"=>nil,
        "mcollective"=>nil,
        "puppetmaster"=>nil
      }
    }

    spec[:master_enc]={
    }

    spec[:networks] = ['mgmt', 'prod', 'front']

    spec[:image_size] = '10G'

    spec[:aliases] = ['puppet','broker']
    return spec
  end
end
