require 'stacks/namespace'
require 'socket'

class Stacks::MachineDef
  attr_reader :hostname, :domain, :environment, :fabric, :domain
  attr_accessor :ram

  def initialize(base_hostname, networks = [:mgmt,:prod], location = :primary_site)
    @base_hostname = base_hostname
    @networks = networks
    @location = location
    @availability_group = nil
    @ram = "2097152"
  end

  def parent
    Socket.gethostname
  end

  def parent_hostname
    get_hostname_from_fqdn(parent)
  end

  def get_hostname_from_fqdn(fqdn)
    case fqdn
      when /^([\w-]+)/
        $1
      else
        fqdn
    end
  end

  def children
    return []
  end

  def bind_to(environment)
    @environment = environment
    @hostname = environment.name + "-" + @base_hostname
    @fabric = environment.options[@location]
    case @fabric
      when 'local'
        @domain = "#{parent_hostname}.net.local"
      else
        @domain = "#{@fabric}.net.local"
    end

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
