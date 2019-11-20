require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::VpnServer < Stacks::MachineDef
  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @vpns = {}
  end

  def bind_to(environment)
    super(environment)
    if environment.options[:vpn_virtual_router_id].nil?
      fail "Environment '#{environment.name}' needs vpn_virtual_router_id to be set"
    end
    @virtual_router_id = environment.options[:vpn_virtual_router_id]
  end

  def to_enc
    enc = super
    virtual_servers = {}
    @virtual_service.vip_networks.each do |vip_network|
      if vip_network != :front
        virtual_servers[@virtual_service.vip_fqdn(vip_network, fabric)] = { 'type' => 'racoon' }
      end
    end
    enc.merge!('role::vpn' => {
                 'virtual_router_id' => @virtual_router_id,
                 'virtual_servers' => virtual_servers,
                 'vpns' => @vpns
               })
    enc
  end

  def add_vpn(vpn)
    local_vpn_endpoint = @virtual_service.vip_fqdn(vpn[:network_of_local_endpoint], fabric)
    @vpns[local_vpn_endpoint] = {} if @vpns[local_vpn_endpoint].nil?
    local_endpoint = @vpns[local_vpn_endpoint]
    local_endpoint[vpn[:remote_vpn_endpoint]] = {} if local_endpoint[vpn[:remote_vpn_endpoint]].nil?
    remote_endpoint = local_endpoint[vpn[:remote_vpn_endpoint]]
    remote_endpoint['networks'] = vpn[:networks]
    remote_endpoint['settings'] = vpn[:settings] unless vpn[:settings].nil?
  end
end
