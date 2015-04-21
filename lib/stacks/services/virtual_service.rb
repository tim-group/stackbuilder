require 'stacks/namespace'

module Stacks::Services::AbstractVirtualService
end

module Stacks::Services::VirtualService
  include Stacks::Services::AbstractVirtualService

  def self.extended(object)
    object.configure
  end

  attr_accessor :ehcache, :nat, :persistent_ports, :healthcheck_timeout, :proto
  attr_reader :vip_networks, :included_classes

  def configure
    @included_classes = {}
    @ehcache = false
    @nat = false
    @persistent_ports = []
    @port_map = {}
    @healthcheck_timeout = 10
    @vip_networks = [:prod]
    @tcp = true
    @udp = false
  end

  def to_loadbalancer_config
    lb_config
  end

  def clazz
    'virtualservice'
  end

  def realservers
    @definitions.values.reject do |server|
      server.fabric != fabric
    end
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
      [network, vip_fqdn(network)]
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

  def remove_vip_network(network)
    @vip_networks.delete network
  end

  def enable_nat
    @nat = true
    add_vip_network :front
    add_vip_network :prod
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def enable_persistence(port)
    @persistent_ports << port
  end

  def nat_rules
    rules = []
    @ports.map do |back_port|
      front_port = @port_map[back_port] || back_port
      front_uri = URI.parse("http://#{vip_fqdn(:front)}:#{front_port}")
      prod_uri = URI.parse("http://#{vip_fqdn(:prod)}:#{back_port}")
      rules << Stacks::Services::Nat.new(front_uri, prod_uri, @tcp, @udp)
    end
    rules
  end

  def config_params(_dependant)
    {}
  end

  private

  def lb_config
    fewest_servers_in_a_group = realservers.size
    grouped_realservers = realservers.group_by(&:group)
    realservers = Hash[grouped_realservers.map do |group, rs|
      fewest_servers_in_a_group = rs.size unless rs.size > fewest_servers_in_a_group
      realserver_fqdns = rs.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    monitor_warn = fewest_servers_in_a_group == 1 ? 0 : 1

    {
      vip_fqdn(:prod) => {
        'env' => environment.name,
        'app' => application,
        'realservers' => realservers,
        'monitor_warn' => monitor_warn,
        'healthcheck_timeout' => healthcheck_timeout
      }
    }
  end
end
