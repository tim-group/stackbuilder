require 'stackbuilder/stacks/namespace'

module Stacks::Services::AbstractVirtualService
end

module Stacks::Services::VirtualService
  include Stacks::Services::AbstractVirtualService
  include Stacks::Services::CanBeNatted

  def self.extended(object)
    object.configure
  end

  attr_accessor :ehcache, :persistent_ports, :healthcheck_timeout, :proto
  attr_reader :vip_networks, :included_classes

  def configure
    @included_classes = {}
    @ehcache = false
    @persistent_ports = []
    @port_map = {}
    @healthcheck_timeout = 10
    @vip_networks = [:prod]
    @tcp = true
    @udp = false
    @nat_config = NatConfig.new(false, false, :front, :prod, true, false, @port_map)
    @dnat_config = @nat_config
    @snat_config = @nat_config
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
    actual_network = (networks.include? network) ? network : networks[0]
    domain = environment.domain(fabric, actual_network)
    "#{environment.name}-#{name}-vip.#{domain}"
  end

  def to_vip_spec(location)
    fabric = environment.options[location]
    qualified_hostnames = Hash[networks.sort.map { |network| [network, vip_fqdn(network, fabric)] }]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => fabric,
      :networks => networks,
      :qualified_hostnames => qualified_hostnames
    }
  end

  def add_vip_network(network)
    @vip_networks << network unless networks.include? network
  end

  def remove_vip_network(network)
    @vip_networks.delete network
  end

  def networks
    natting_networks = [:front, :prod]
    dnat_networks = @dnat_config.inbound_enabled ? natting_networks : []
    snat_networks = @snat_config.outbound_enabled ? natting_networks : []

    (@vip_networks + dnat_networks + snat_networks).uniq
  end

  def enable_nat
    configure_dnat(:front, :prod, @tcp, @udp, @port_map)
  end

  # nat_out means setup a specific outgoing snat rule from the prod vip of the
  # virtual service to the front vip of the virtual service (rather than the
  # default nat vip, if there is one)
  def enable_nat_out
    configure_snat(:front, :prod, @tcp, @udp, @port_map)
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def enable_persistence(port)
    @persistent_ports << port
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
