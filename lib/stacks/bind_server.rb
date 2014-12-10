require 'stacks/namespace'
require 'stacks/machine_def'
require 'resolv'

class Stacks::BindServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service

  def initialize(base_hostname, virtual_service, role, index, &block)
    @role = role
    super(base_hostname, [:mgmt,:prod], :primary_site)
    @virtual_service = virtual_service
  end

  def role
    @role
  end

  def master?
    @role == :master
  end

  def slave?
    @role == :slave
  end

  def bind_to(environment)
    super(environment)
  end

  def vip_fqdn(net)
    return @virtual_service.vip_fqdn(net)
  end

  def slave_from(env)
    @virtual_service.depend_on('ns', env)
  end

  def to_enc()
    dependant_zones = @virtual_service.bind_master_servers_and_zones_that_i_depend_on

    enc = super()
    vip_fqdns = @virtual_service.vip_networks.map do |vip_network|
      if [:front].include? vip_network
        nil
      else
        vip_fqdn(vip_network)
      end
    end
    vip_fqdns.compact!
    enc.merge!({
      'role::bind_server' => {
        'vip_fqdns'                         => vip_fqdns,
        'participation_dependant_instances' => @virtual_service.dependant_load_balancer_machine_def_fqdns([:mgmt,:prod]),
        'dependant_instances'               => @virtual_service.all_dependencies(self),
        'forwarder_zones'                   => @virtual_service.forwarder_zones,
      },
      'server::default_new_mgmt_net_local'  => nil,
    })
    enc['role::bind_server']['master_zones'] = @virtual_service.zones_fqdn if master?

    enc['role::bind_server']['slave_zones'] = @virtual_service.slave_zones_fqdn(self) unless @virtual_service.slave_zones_fqdn(self).nil?
    unless dependant_zones.nil?
      if enc['role::bind_server']['slave_zones'].nil?
        enc['role::bind_server']['slave_zones'] = dependant_zones
      else
        enc['role::bind_server']['slave_zones'].merge! dependant_zones
      end
    end

    enc
  end

  def to_spec
    spec = super
    spec[:nameserver] = Resolv.getaddress(@virtual_service.slave_servers.first.mgmt_fqdn) if master?
    spec[:nameserver] = Resolv.getaddress(@virtual_service.master_server.mgmt_fqdn) unless master?
    spec[:networks] = @virtual_service.vip_networks.select do |vip_network|
      not [:front].include? vip_network
    end
    spec[:qualified_hostnames] = Hash[spec[:networks].map { |network| [network, qualified_hostname(network)] }]
    spec
  end
end
