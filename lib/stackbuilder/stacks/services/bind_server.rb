require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'
require 'resolv'

class Stacks::Services::BindServer < Stacks::MachineDef
  attr_reader :site

  def master?
    @role == :master
  end

  def slave?
    @role == :slave
  end

  def to_enc
    dependant_zones = @virtual_service.bind_master_servers_and_zones_that_i_depend_on(location)

    enc = super()
    vip_fqdns = @virtual_service.networks.map do |vip_network|
      if [:front].include? vip_network
        nil
      else
        @virtual_service.vip_fqdn(vip_network, fabric)
      end
    end
    vip_fqdns.compact!
    enc.merge!('role::bind_server' => {
                 'vip_fqdns'                         => vip_fqdns,
                 'participation_dependant_instances' =>
                   @virtual_service.dependant_load_balancer_fqdns(location, @networks),
                 'dependant_instances'               => @virtual_service.all_dependencies(self),
                 'forwarder_zones'                   => @virtual_service.forwarder_zones,
                 'allowed_hosts'                    => @virtual_service.allowed_hosts
               })
    enc['role::bind_server']['master_zones'] = @virtual_service.zones_fqdn_for_site(site) if master?
    enc['role::bind_server']['slave_zones'] = @virtual_service.slave_zones_fqdn_for_site(site) unless master?

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
    case @role
    when :master
      spec[:nameserver] = Resolv.getaddress(@virtual_service.slave_servers_as_fqdns.first)
    when :slave
      spec[:nameserver] = Resolv.getaddress(@virtual_service.master_server.mgmt_fqdn)
    end
    spec
  end
end
