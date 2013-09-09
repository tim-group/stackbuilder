require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/rabbitmq_server'
require 'stacks/nat'
require 'uri'

module Stacks::VirtualRabbitMQService

  def self.extended(object)
    object.configure()
  end

  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def configure()
    @downstream_services = []
    @ports = [5672]
  end

  def realserver_prod_fqdns
    self.realservers.map { |server| server.prod_fqdn }.sort
  end

  def to_loadbalancer_config
    realservers = {'blue' => realserver_prod_fqdns}

    [self.vip_fqdn, {
      'type' => 'rabbitmq',
      'ports' => @ports,
      'realservers' => realservers
    }]
  end
end
