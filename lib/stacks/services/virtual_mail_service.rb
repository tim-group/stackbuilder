module Stacks::Services::VirtualMailService
  def self.extended(object)
    object.configure
  end

  def configure
    @ports = [25]
    add_vip_network :mgmt
    remove_vip_network :prod
  end

  def to_loadbalancer_config
    vip_nets = @vip_networks.select do |vip_network|
      ![:front].include? vip_network
    end
    lb_config = {}
    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net)] = {
        'type'         => 'mail',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => realservers.map { |server| server.qualified_hostname(vip_net) }.sort
        }
      }
    end
    lb_config
  end
end
