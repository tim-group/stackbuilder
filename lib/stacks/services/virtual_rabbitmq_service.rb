require 'stacks/namespace'

module Stacks::Services::VirtualRabbitMQService
  def self.extended(object)
    object.configure
  end

  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def configure
    @downstream_services = []
    @ports = [5672]
  end

  def realserver_prod_fqdns
    realservers.map(&:prod_fqdn).sort
  end

  def to_loadbalancer_config
    realservers = { 'blue' => realserver_prod_fqdns }

    {
      vip_fqdn(:prod) => {
        'type' => 'rabbitmq',
        'ports' => @ports,
        'realservers' => realservers
      }
    }
  end
end
