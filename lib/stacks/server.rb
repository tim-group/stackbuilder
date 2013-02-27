require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server < Stacks::MachineDef
  attr_reader :environment, :virtual_group

  def initialize(virtual_service, index, location, &block)
    @virtual_service = virtual_service
    @virtual_group = virtual_service.name
    @index = index
    @location = location
    @networks = [:mgmt, :prod]
    block.call unless block.nil?
  end

  def bind_to(environment)
    @environment = environment
    @hostname = environment.name + "-" + @virtual_group + "-" + @index
    @fabric = environment.options[@location]
    @domain = "#{@fabric}.net.local"
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
    @availability_group = environment.name + "-" + @virtual_group
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def groups
    return ['blue']
  end

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :group => @availability_group,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }]
  end
end
