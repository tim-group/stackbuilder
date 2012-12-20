require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :environment
  attr_reader :hostname

  def initialize(hostname, environment)
    @hostname = hostname
    @environment = environment
  end

  def to_spec
    return {
      :hostname=>hostname,
      :domain=>"dev.net.local",
      :template=>"seedapply",
      :env=>"dev",
      :enc=>{
        "classes"=>{
          "base"=>nil,
          "mcollective"=>nil,
          "puppetagent"=>{
            "puppetmaster"=>"dev-puppetmaster-001.dev.net.local"
          }}
      }
    }
  end
end
