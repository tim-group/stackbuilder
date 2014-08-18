require 'stacks/namespace'
require 'facter'

class Stacks::MachineDef
  attr_accessor :availability_group
  attr_reader :hostname, :domain, :environment
  attr_accessor :fabric, :image_size, :networks, :ram, :storage, :vcpus

  def initialize(base_hostname, networks = [:mgmt,:prod], location = :primary_site)
    @base_hostname = base_hostname
    @networks = networks
    @location = location
    @availability_group = nil
    @ram = "2097152"
    @storage = {
      '/'.to_sym =>  {
        :type        => 'os',
        :size        => '3G',
        :prepare     => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      }
    }
  end

  def children
    return []
  end

  def needs_signing?
    true
  end

  def needs_poll_signing?
    true
  end

  def fabric
    @fabric
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
        @hostname = "#{@hostname}-#{owner_fact}"
    end
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
  end

  def owner_fact()
    unless $LOAD_PATH.include?('/var/lib/puppet/lib')
      $LOAD_PATH << '/var/lib/puppet/lib'
    end
    Facter.loadfacts
    if Facter.value('owner') == nil
      'OWNER-FACT-NOT-FOUND'
    else
      Facter.value 'owner'
    end
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

  def modify_storage(storage_modifications)
    storage_modifications.each do |mount_point, values|
       if @storage[mount_point.to_sym].nil?
         @storage[mount_point.to_sym] = values
       else
         @storage[mount_point.to_sym] = recurse_merge(@storage[mount_point.to_sym], values)
       end
    end
  end

  def recurse_merge(a,b)
    a.merge(b) do |_,x,y|
      (x.is_a?(Hash) && y.is_a?(Hash)) ? recurse_merge(x,y) : y
    end
  end

  def legacy_override_root_storage_using_image_size
    modify_storage({
      '/'.to_sym => {
        :size => image_size
      }
    })
  end

  def storage
    legacy_override_root_storage_using_image_size if image_size
    return @storage
  end

  def to_spec
    spec = {
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :availability_group => availability_group,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }

    spec[:ram] = ram unless ram.nil?
    spec[:vcpus] = vcpus unless vcpus.nil?
    spec[:image_size] = image_size unless image_size.nil?
    spec[:storage] = storage
    spec
  end

  # DEPRECATED for flatten / accept interface, remove me!
  def to_specs
    [ to_spec ]
  end

  def to_enc
    return {}
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
