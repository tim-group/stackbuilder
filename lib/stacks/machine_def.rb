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
      :env=>"dev"
    }
  end
end
