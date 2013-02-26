require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::StandaloneServer < Stacks::MachineDef
  attr_reader :environment

  def initialize(base_hostname, location, &block)
    @base_hostname = base_hostname
    @location = location
    @networks = [:mgmt, :prod]
    block.call unless block.nil?
  end

  def bind_to(environment)
    @hostname = environment.name + "-" + @base_hostname
    @environment = environment
    @fabric = environment.options[@location]
    @domain = "#{@fabric}.net.local"
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
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
    return qualified_hostname(:mgmt)
  end

  def groups
    return ['blue']
  end

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }]
  end
end
