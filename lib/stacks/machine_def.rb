require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname, :domain, :environment
  attr_accessor :availability_group
  attr_reader :fabric, :networks
  attr_accessor :ram, :image_size, :vcpus

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
    suffix = 'net.local'
    @domain = "#{@fabric}.#{suffix}"
    case @fabric
      when 'local'
        @domain = "dev.#{suffix}"
    end
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
  end

  def accept(&block)
    block.call(self)
  end

  def flatten
    return [self]
  end

  def name
    return hostname
  end

  def to_spec
    spec = {
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :group => @availability_group,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }

    spec[:ram] = ram unless ram.nil?
    spec[:vcpus] = vcpus unless vcpus.nil?
    spec[:image_size] = image_size unless image_size.nil?

    spec
  end

  # DEPRECATED for flatten / accept interface, remove me!
  def to_specs
    [ to_spec ]
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
