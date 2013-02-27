
require 'stacks/namespace'

class Stacks::LoadBalancer < Stacks::MachineDef
  attr_reader :environment

  def bind_to(environment)
    @environment = environment
    @hostname = environment.name + "-" + @hostname
    @fabric = environment.options[:primary]
    @domain = "#{@fabric}.net.local"
    @networks = [:mgmt, :prod]
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
  end

  def virtual_services
    virtual_services = environment.accept do |name, node|
      node.kind_of? ::Stacks::VirtualService
    end
  end
end
