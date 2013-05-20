require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'


class Stacks::MachineSet
  attr_accessor :type
  attr_accessor :name
  attr_accessor :fabric
  attr_accessor :instances
  attr_accessor :ports
  attr_accessor :groups

  include Stacks::MachineDefContainer

  def initialize(name, &config_block)
    @name = name
    @groups = ['blue']
    @definitions = {}
    @bind_steps = []
    @instances = 2
    @config_block = config_block
  end

  def on_bind(&block)
    @bind_steps << block
  end

  def bind_to(environment)
    @bind_steps.each do |step|
      step.call(self, environment)
    end
  end
end

module Stacks::AbstractVirtualService
end

module Stacks::XVirtualService
  include Stacks::AbstractVirtualService

  def self.extended(object)
    object.configure()
  end

  attr_accessor :nat

  def configure_domain_name(environment)
    @fabric = environment.options[:primary_site]
    suffix = 'net.local'
    @domain = "#{@fabric}.#{suffix}"
    case @fabric
    when 'local'
      @domain = "dev.#{suffix}"
    end
  end

  def instantiate_machines(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::AppServer.new(self, index, &@config_block)
      server.group = groups[i%groups.size]
      server.ram   = @ram unless @ram.nil?
    end
  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def configure()
    @nat=false
    @port_map = {}

    on_bind do |machineset, environment|
      @environment = environment
      configure_domain_name(environment)
      self.instance_eval(&@config_block) unless @config_block.nil?
      instantiate_machines(environment)
      bind_children(environment)
   end
  end

  def to_loadbalancer_config
    grouped_realservers = self.realservers.group_by do |realserver|
      realserver.group
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map do |realserver|
        realserver.prod_fqdn
      end.sort
      [group, realserver_fqdns]
    end]

    [self.vip_fqdn, {
      'env' => self.environment.name,
      'app' => self.application,
      'realservers' => realservers
    }]

  end

  def clazz
    return 'virtualservice'
  end

  def realservers
    return @definitions.values
  end

  def vip_fqdn
    "#{environment.name}-#{name}-vip.#{@domain}"
  end

  def vip_front_fqdn
    "#{environment.name}-#{name}-vip.front.#{@domain}"
  end

  def to_vip_spec
    networks = (nat==true)? [:prod, :front]: [:prod]
    qualified_hostnames = Hash[networks.map do |network|
      pair = nil
      if network == :prod
        pair = [network, vip_fqdn]
      end
      if network == :front
        pair = [network, vip_front_fqdn]
      end
      pair
    end]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => @fabric,
        :networks => networks,
        :qualified_hostnames => qualified_hostnames
    }
  end

  def enable_nat
    @nat = true
  end

  def nat_rules
    rules = []
    @ports.map do |back_port|
      front_port = @port_map[back_port] || back_port
      front_uri = URI.parse("http://#{vip_front_fqdn}:#{front_port}")
      prod_uri = URI.parse("http://#{vip_fqdn}:#{back_port}")
      rules << Stacks::Nat.new(front_uri, prod_uri)
    end
    rules
  end

end

module Stacks::XVirtualAppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application

  def configure()
  end

end

class Stacks::VirtualService
  attr_reader :name
  attr_reader :environment
  attr_reader :nat
  attr_reader :domain
  attr_reader :fabric
  attr_accessor :ports
  attr_accessor :port_map
  attr_accessor :instances

  include Stacks::MachineDefContainer
  include Stacks::AbstractVirtualService

  def initialize(name, &config_block)
    @name = name
    @definitions = {}
    @instances = 2
    @config_block = config_block
    @port_map = {}
    @nat=false
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary_site]
    suffix = 'net.local'
    @domain = "#{@fabric}.#{suffix}"
    case @fabric
    when 'local'
      @domain = "dev.#{suffix}"
    end
    super(environment)
    self.instance_eval(&@config_block) unless @config_block.nil?
  end

  def clazz
    return 'virtualservice'
  end

  ## virtual server stuff
  def realservers
    return @definitions.values
  end

  def vip_fqdn
    "#{environment.name}-#{name}-vip.#{@domain}"
  end

  def vip_front_fqdn
    "#{environment.name}-#{name}-vip.front.#{@domain}"
  end

  def to_vip_spec
    networks = (nat==true)? [:prod, :front]: [:prod]
    qualified_hostnames = Hash[networks.map do |network|
      pair = nil
      if network == :prod
        pair = [network, vip_fqdn]
      end
      if network == :front
        pair = [network, vip_front_fqdn]
      end
      pair
    end]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => @fabric,
        :networks => networks,
        :qualified_hostnames => qualified_hostnames
    }
  end

  def enable_nat
    @nat = true
  end

  def nat_rules
    rules = []
    @ports.map do |back_port|
      front_port = @port_map[back_port] || back_port
      front_uri = URI.parse("http://#{vip_front_fqdn}:#{front_port}")
      prod_uri = URI.parse("http://#{vip_fqdn}:#{back_port}")
      rules << Stacks::Nat.new(front_uri, prod_uri)
    end
    rules
  end
end
