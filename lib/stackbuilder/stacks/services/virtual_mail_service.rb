module Stacks::Services::VirtualMailService
  def self.extended(object)
    object.configure
  end

  def configure
    @ports = [25]
    add_vip_network :mgmt
  end

  def to_loadbalancer_config(location, fabric)
    vip_nets = @vip_networks.select do |vip_network|
      ![:front].include? vip_network
    end
    lb_config = {}
    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net, fabric)] = {
        'type'         => 'mail',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => realservers(location).map { |server| server.qualified_hostname(vip_net) }.sort
        }
      }
    end
    lb_config
  end

  def endpoints(_dependent_service, fabric)
    endpoints = []
    @ports.each do |port|
      endpoints << { :port => port, :fqdns => [vip_fqdn(:prod, fabric)] }
    end
    endpoints
  end

  def config_params(_dependant, fabric, dependent_service)
    mail_server = endpoints(dependent_service, fabric).map do |endpoint|
      "#{endpoint[:fqdns].first}:#{endpoint[:port]}"
    end
    {
      "smtp.server" => mail_server.join(',')
    }
  end
end
