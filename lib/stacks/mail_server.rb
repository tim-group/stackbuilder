require 'stacks/namespace'
require 'stacks/machine_def'
require 'resolv'

class Stacks::MailServer < Stacks::MachineDef
  attr_reader :environment
  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    enc = super()
    vip_fqdns = @virtual_service.vip_networks.map do |vip_network|
      if [:front].include? vip_network
        nil
      else
        @virtual_service.vip_fqdn(vip_network)
      end
    end

    vip_fqdns.compact!
    enc.merge!('role::mail_server2' => {
                 'allowed_hosts'       => @virtual_service.allowed_hosts,
                 'vip_fqdns'           => vip_fqdns,
                 'vip_networks'        => @virtual_service.vip_networks.map(&:to_s),
                 'dependant_instances' => @virtual_service.dependant_load_balancer_machine_def_fqdns(@virtual_service.vip_networks),
                 'participation_dependant_instances' => @virtual_service.dependant_load_balancer_machine_def_fqdns(@virtual_service.vip_networks)
               },
               'server::default_new_mgmt_net_local' => nil)
    enc
  end
end
