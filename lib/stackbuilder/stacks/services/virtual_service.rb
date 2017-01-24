require 'stackbuilder/stacks/namespace'

module Stacks::Services::AbstractVirtualService
end

module Stacks::Services::VirtualService
  include Stacks::Services::AbstractVirtualService
  include Stacks::Services::CanBeNatted

  def self.extended(object)
    object.configure
  end

  attr_accessor :ehcache, :nat_config, :nat, :nat_out, :nat_out_exclusive, :persistent_ports,
                :healthcheck_timeout, :proto
  attr_reader :vip_networks, :included_classes

  def configure
    @included_classes = {}
    @ehcache = false
    @nat = false
    @nat_out = false
    @nat_out_exclusive = false
    @persistent_ports = []
    @port_map = {}
    @healthcheck_timeout = 10
    @vip_networks = [:prod]
    @tcp = true
    @udp = false
    @nat_config = NatConfig.new(false, :front, :prod, true, false, {})
  end

  def clazz
    'virtualservice'
  end

  def type_of?
    :virtual_service
  end

  def identity
    "#{environment.name}_#{name.to_sym}"
  end

  def realservers(location)
    @definitions.values.select { |server| server.location == location }
  end

  def vip_fqdn(network, fabric)
    actual_network = (@vip_networks.include? network) ? network : @vip_networks[0]
    domain = environment.domain(fabric, actual_network)
    "#{environment.name}-#{name}-vip.#{domain}"
  end

  def to_vip_spec(location)
    fabric = environment.options[location]
    qualified_hostnames = Hash[@vip_networks.sort.map { |network| [network, vip_fqdn(network, fabric)] }]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => fabric,
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
    add_networks_for_nat
  end

  # nat_out means setup a specific outgoing snat rule from the prod vip of the
  # virtual service to the front vip of the virtual service (rather than the
  # default nat vip, if there is one)
  def enable_nat_out
    @nat_out = true
    add_networks_for_nat
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def enable_persistence(port)
    @persistent_ports << port
  end

  def dnat_rules(location)
    rules = []
    fabric = environment.options[location]
    if @nat
      @ports.map do |back_port|
        front_port = @port_map[back_port] || back_port
        front_uri = URI.parse("http://#{vip_fqdn(:front, fabric)}:#{front_port}")
        prod_uri = URI.parse("http://#{vip_fqdn(:prod, fabric)}:#{back_port}")
        rules << Stacks::Services::Nat.new(front_uri, prod_uri, @tcp, @udp)
      end
    end
    rules
  end

  def snat_rules(location)
    rules = []
    fabric = environment.options[location]
    if @nat_out
      @ports.map do |back_port|
        front_port = @port_map[back_port] || back_port
        front_uri = URI.parse("http://#{vip_fqdn(:front, fabric)}:#{front_port}")
        prod_uri = URI.parse("http://#{vip_fqdn(:prod, fabric)}:#{back_port}")
        rules << Stacks::Services::Nat.new(prod_uri, front_uri, @tcp, @udp)
      end
    end
    rules
  end

  def config_params(_dependant, _fabric)
    {}
  end

  def load_balanced_service?
    true
  end

  def monitor_warn(servers)
    servers == 1 ? 0 : 1
  end

  private

  def add_networks_for_nat
    add_vip_network :front
    add_vip_network :prod
  end

  def loadbalancer_config(location, fabric)
    fewest_servers_in_a_group = realservers(location).size
    return {} if fewest_servers_in_a_group == 0
    grouped_realservers = realservers(location).group_by(&:group)
    realservers_hash = Hash[grouped_realservers.map do |group, rs|
      fewest_servers_in_a_group = rs.size unless rs.size > fewest_servers_in_a_group
      realserver_fqdns = rs.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    {
      vip_fqdn(:prod, fabric) => {
        'env'                 => environment.name,
        'app'                 => application,
        'realservers'         => realservers_hash,
        'monitor_warn'        => monitor_warn(fewest_servers_in_a_group),
        'healthcheck_timeout' => healthcheck_timeout
      }
    }
  end
end
