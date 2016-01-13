require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::VpnServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
    @vpns = {}
  end

  def to_enc
    enc = super
    enc.merge!('server::default_new_mgmt_net_local' => {})
    virtual_servers = {}
    @virtual_service.vip_networks.each do |vip_network|
      if vip_network != :front
        virtual_servers[@virtual_service.vip_fqdn(vip_network, fabric)] = { 'type' => 'racoon' }
      end
    end
    enc.merge!('role::vpn' => {
                 'virtual_servers' => virtual_servers,
                 'vpns' => @vpns
               })
    enc
  end

  def add_vpn_network(network_of_local_endpoint, remote_vpn_endpoint, local_network, remote_network)
    local_vpn_endpoint = @virtual_service.vip_fqdn(network_of_local_endpoint, fabric)
    @vpns[local_vpn_endpoint] = {} if @vpns[local_vpn_endpoint].nil?
    local_endpoint = @vpns[local_vpn_endpoint]
    local_endpoint[remote_vpn_endpoint] = {} if local_endpoint[remote_vpn_endpoint].nil?
    remote_endpoint = local_endpoint[remote_vpn_endpoint]
    remote_endpoint[local_network] = [] if remote_endpoint[local_network].nil?
    local_net = remote_endpoint[local_network]
    local_net << remote_network unless local_net.include? remote_network
  end
end
