require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname, :domain, :environment

  def initialize(base_hostname, networks = [:mgmt,:prod], location = :primary_site)
    @base_hostname = base_hostname
    @networks = networks
    @location = location
    @availability_group = nil
    @ram = "2097152"
  end

  def children
    return []
  end

  def bind_to(environment)
    @environment = environment
    @hostname = environment.name + "-" + @base_hostname
    @fabric = environment.options[@location]
    @domain = "#{@fabric}.net.local"
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
  end

  def accept(&block)
    block.call(self)
  end

  def name
    return hostname
  end

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :group => @availability_group,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }],
      :ram => @ram,
    }]
  end

  def qualified_hostname(network)
    raise "no such network '#{network}'" unless @networks.include?(network)
    if network.eql?(:prod)
      return "#{@hostname}.#{@domain}"
    else
      return "#{@hostname}.#{network}.#{@domain}"
    end
  end

  def prod_fqdn
    return qualified_hostname(:prod)
  end

  def mgmt_fqdn
    return qualified_hostname(:mgmt)
  end

  def clazz
    return "machine"
  end
end
