require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server < Stacks::MachineDef
  def initialize(virtual_group, index, location, &block)
    @virtual_group = virtual_group
    @index = index
    @location = location
    @networks = ["mgmt", "prod"]
    block.call unless block.nil?
  end

  def bind_to(environment)
    @hostname = environment.name + "-" + @virtual_group + "-" + @index
    @fabric = environment.options[@location]
    @domain = "#{@fabric}.net.local"
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
    @availability_group = environment.name + "-" + @virtual_group
  end

  def qualified_hostname(network)
    raise "no such network '#{network}'" unless @networks.include?(network)
    if network == 'prod'
      return "#{@hostname}.#{@domain}"
    else
      return "#{@hostname}.#{network}.#{@domain}"
    end
  end

  def mgmt_fqdn
    return qualified_hostname("mgmt")
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
