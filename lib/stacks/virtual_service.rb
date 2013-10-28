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

  attr_accessor :nat, :persistent_ports

  def configure()
    @nat=false
    @persistent_ports = []
    @port_map = {}
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

    [self.vip_fqdn, {
      'env' => self.environment.name,
      'app' => self.application,
      'realservers' => realservers,
      'monitor_warn' => monitor_warn,
      'healthcheck_timeout' => 10
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

  def enable_persistence(port)
    @persistent_ports << port
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
