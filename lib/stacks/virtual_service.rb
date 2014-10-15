require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::AbstractVirtualService
end

module Stacks::MachineGroup
  def self.extended(object)
    object.configure()
  end

  def configure()
    on_bind do |machineset, environment|
      @environment = environment
      configure_domain_name(environment)
      self.instance_eval(&@config_block) unless @config_block.nil?
      instantiate_machines(environment)
      bind_children(environment)
    end
  end

  def configure_domain_name(environment)
    @fabric = environment.options[:primary_site]
    suffix = 'net.local'
    @domain = "#{@fabric}.#{suffix}"
    case @fabric
    when 'local'
      @domain = "dev.#{suffix}"
    end
  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def availability_group(environment)
    environment.name + "-" + self.name
  end

  def instantiate_machines(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = @type.new(self, index, &@config_block)
      if server.respond_to?(:group)
        server.group = groups[i%groups.size]
      end

      if server.respond_to?(:availability_group)
        server.availability_group = availability_group(environment)
      end
    end
  end
end

module Stacks::VirtualService
  include Stacks::AbstractVirtualService

  def self.extended(object)
    object.configure()
  end

  attr_accessor :ehcache, :nat, :persistent_ports, :healthcheck_timeout, :proto

  def configure()
    @ehcache = false
    @nat=false
    @persistent_ports = []
    @port_map = {}
    @healthcheck_timeout = 10
    @vip_networks = [:prod]
    @tcp = true
    @udp = false
  end

  def to_loadbalancer_config
    fewest_servers_in_a_group = self.realservers.size
    grouped_realservers = self.realservers.group_by do |realserver|
      realserver.group
    end
    num_servers_in_group = {}
    realservers = Hash[grouped_realservers.map do |group, realservers|
      fewest_servers_in_a_group = realservers.size unless realservers.size > fewest_servers_in_a_group
      realserver_fqdns = realservers.map do |realserver|
        realserver.prod_fqdn
      end.sort
      [group, realserver_fqdns]
    end]

    monitor_warn = fewest_servers_in_a_group == 1 ? 0 : 1

    {
      self.vip_fqdn(:prod) => {
        'env' => self.environment.name,
        'app' => self.application,
        'realservers' => realservers,
        'monitor_warn' => monitor_warn,
        'healthcheck_timeout' => self.healthcheck_timeout
      }
    }
  end

  def clazz
    return 'virtualservice'
  end

  def realservers
    return @definitions.values
  end

  def vip_fqdn(net)
    case net
    when nil, :prod
      "#{environment.name}-#{name}-vip.#{@domain}"
    else
      "#{environment.name}-#{name}-vip.#{net}.#{@domain}"
    end
  end

  def to_vip_spec
    qualified_hostnames = Hash[@vip_networks.map do |network|
      pair = [network, vip_fqdn(network)]
    end]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => @fabric,
        :networks => @vip_networks,
        :qualified_hostnames => qualified_hostnames
    }
  end

  def add_vip_network(network)
    @vip_networks << network unless @vip_networks.include? network
  end

  def enable_nat
    @nat = true
    add_vip_network :front
  end

  def enable_persistence(port)
    @persistent_ports << port
  end

  def nat_rules()
    rules = []
    @ports.map do |back_port|
      front_port = @port_map[back_port] || back_port
      front_uri = URI.parse("http://#{vip_fqdn(:front)}:#{front_port}")
      prod_uri = URI.parse("http://#{vip_fqdn(:prod)}:#{back_port}")
      rules << Stacks::Nat.new(front_uri, prod_uri, @tcp, @udp)
    end
    rules
  end

  def config_params(dependant)
    {}
  end

end
