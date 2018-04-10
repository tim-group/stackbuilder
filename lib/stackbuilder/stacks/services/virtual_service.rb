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
  attr_accessor :vip_warning_members, :vip_critical_members
  attr_reader :vip_networks, :included_classes

  def configure
    @included_classes = {}
    @ehcache = false
    @persistent_ports = []
    @healthcheck_timeout = 10
    @vip_networks = [:prod]
    @nat_config = NatConfig.new(false, false, :front, :prod, true, false)
    @vip_warning_members = nil
    @vip_critical_members = 0
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
    natting_networks = @nat_config.dnat_enabled || @nat_config.snat_enabled ? @nat_config.networks : []
    (@vip_networks + natting_networks).uniq
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def enable_persistence(port)
    @persistent_ports << port
  end

  def config_params(_dependant, _fabric, _dependent_instance)
    {}
  end

  def load_balanced_service?
    true
  end

  def calc_vip_warning_members(servers)
    servers == 1 ? 0 : 1
  end

  private

  def loadbalancer_config(location, fabric)
    servers = realservers(location).size
    return {} if servers == 0
    grouped_realservers = realservers(location).group_by(&:group)
    realservers_hash = Hash[grouped_realservers.map do |group, rs|
      servers = rs.size unless rs.size > servers
      realserver_fqdns = rs.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    {
      vip_fqdn(:prod, fabric) => {
        'env'                 => environment.name,
        'app'                 => application,
        'realservers'         => realservers_hash,
        'monitor_warn'        => vip_warning_members.nil? ? calc_vip_warning_members(servers) : vip_warning_members,
        'monitor_critical'    => vip_critical_members,
        'healthcheck_timeout' => healthcheck_timeout
      }
    }
  end
end
