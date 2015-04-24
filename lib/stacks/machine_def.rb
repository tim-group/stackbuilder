require 'stacks/namespace'
require 'facter'

class Stacks::MachineDef
  attr_reader :domain
  attr_reader :environment
  attr_reader :fabric
  attr_reader :hostname
  attr_accessor :availability_group
  attr_accessor :fabric
  attr_accessor :networks
  attr_accessor :ram
  attr_accessor :storage
  attr_accessor :vcpus

  def initialize(base_hostname, networks = [:mgmt, :prod], location = :primary_site)
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
            :path => '/var/local/images/gold-precise/generic.img'
          }
        }
      }
    }
    @destroyable = true
    @dont_start = false
    @routes = []
    @included_classes = {}
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def use_trusty
    trusty_gold_image = {
      '/'.to_sym =>  {
        :prepare     => {
          :options => {
            :path => '/var/local/images/gold-trusty/generic.img'
          }
        }
      }
    }
    modify_storage(trusty_gold_image)
  end

  def needs_signing?
    true
  end

  # rubocop:disable Style/TrivialAccessors
  def destroyable?
    @destroyable
  end
  # rubocop:enable Style/TrivialAccessors

  def needs_poll_signing?
    true
  end

  # rubocop:disable Style/TrivialAccessors
  def allow_destroy(destroyable = true)
    @destroyable = destroyable
  end
  # rubocop:enable Style/TrivialAccessors

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
    fail "domain must not contain mgmt" if @domain =~ /mgmt\./
  end

  def disable_persistent_storage
    @storage.each do |mount_point, _values|
      modify_storage(mount_point.to_sym => { :persistent => false })
    end
  end

  # this used to be the 'owner' fact set by puppet, but looking it up with the Facter module was incredibly slow
  # the following code recreates the logic from puppet
  # caching `hostname` in @@localhost_hostname is a major speedup (0.5 seconds as of 24.04.2015 on a dev box)
  # rubocop:disable Style/ClassVars
  def owner_fact
    @@localhost_hostname = `hostname` if !defined? @@localhost_hostname
    case @@localhost_hostname
    when /^\w{3}-dev-(\w+)/ then $1
    when /^(\w+)-desktop/   then $1
    else 'OWNER-FACT-NOT-FOUND'
    end
  end
  # rubocop:enable Style/ClassVars

  def accept(&block)
    block.call(self)
  end

  def flatten
    [self]
  end

  def name
    hostname
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

  def remove_network(net)
    @networks.delete net
  end

  def recurse_merge(a, b)
    a.merge(b) do |_, x, y|
      (x.is_a?(Hash) && y.is_a?(Hash)) ? recurse_merge(x, y) : y
    end
  end

  def add_route(route_name)
    @routes << route_name unless @routes.include? route_name
  end

  def dont_start
    @dont_start = true
  end

  def to_spec
    disable_persistent_storage unless environment.persistent_storage_supported?
    @destroyable = true if environment.every_machine_destroyable?

    spec = {
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :availability_group => availability_group,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }

    spec[:disallow_destroy] = true unless @destroyable
    spec[:ram] = ram unless ram.nil?
    spec[:vcpus] = vcpus unless vcpus.nil?
    spec[:storage] = storage
    spec[:dont_start] = true if @dont_start
    spec
  end

  # XXX DEPRECATED for flatten / accept interface, remove me!
  def to_specs
    [to_spec]
  end

  def to_enc
    enc = {}
    enc.merge! @included_classes
    enc.merge! @virtual_service.included_classes if @virtual_service && @virtual_service.respond_to?(:included_classes)
    unless @routes.empty?
      enc['routes'] = {
        'to' => @routes
      }
    end
    enc
  end

  def qualified_hostname(network)
    fail "no such network '#{network}'" unless @networks.include?(network)
    if network.eql?(:prod)
      return "#{@hostname}.#{@domain}"
    else
      return "#{@hostname}.#{network}.#{@domain}"
    end
  end

  def prod_fqdn
    qualified_hostname(:prod)
  end

  def mgmt_fqdn
    qualified_hostname(:mgmt)
  end

  def clazz
    "machine"
  end
end
