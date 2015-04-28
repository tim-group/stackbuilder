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

  def clazz
    'virtualservice'
  end

  def realservers(location)
    @definitions.values.select { |server| server.location == location }
  end

  def vip_fqdn(network, location)
    fabric = environment.options[location]
    fail "Unable to determine fabric for #{location}" if fabric.nil?
    domain = environment.domain(fabric, network)
    "#{environment.name}-#{name}-vip.#{domain}"
  end

  ## FIXME: We should not have to specify a default location
  def to_vip_spec(location = :primary_site)
    qualified_hostnames = Hash[@vip_networks.map do |network|
      [network, vip_fqdn(network, location)]
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

  def nat_rules(location)
    rules = []
    @ports.map do |back_port|
      front_port = @port_map[back_port] || back_port
      front_uri = URI.parse("http://#{vip_fqdn(:front, location)}:#{front_port}")
      prod_uri = URI.parse("http://#{vip_fqdn(:prod, location)}:#{back_port}")
      rules << Stacks::Services::Nat.new(front_uri, prod_uri, @tcp, @udp)
    end
    rules
  end

  def config_params(_dependant, _location)
    {}
  end

  def load_balanced_service?
    true
  end

  private

  def loadbalancer_config(location)
    fewest_servers_in_a_group = realservers(location).size
    grouped_realservers = realservers(location).group_by(&:group)
    realservers_hash = Hash[grouped_realservers.map do |group, rs|
      fewest_servers_in_a_group = rs.size unless rs.size > fewest_servers_in_a_group
      realserver_fqdns = rs.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    monitor_warn = fewest_servers_in_a_group == 1 ? 0 : 1

    {
      vip_fqdn(:prod, location) => {
        'env' => environment.name,
        'app' => application,
        'realservers' => realservers_hash,
        'monitor_warn' => monitor_warn,
        'healthcheck_timeout' => healthcheck_timeout
      }
    }
  end
end
