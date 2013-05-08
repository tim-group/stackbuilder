require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/rabbitmq_server'
require 'stacks/nat'
require 'uri'

class Stacks::VirtualRabbitMQService < Stacks::VirtualService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def initialize(name, &config_block)
    super(name, &config_block)
    @downstream_services = []
    @config_block = config_block
    @ports = [5672]
  end

  def bind_to(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::RabbitMQServer.new(self, index, &@config_block)
    end
    super(environment)
  end

  def realserver_prod_fqdns
    self.realservers.map { |server| server.prod_fqdn }.sort
  end

  def to_loadbalancer_config
    realservers = {'blue' => realserver_prod_fqdns}

    [self.vip_fqdn, {
      'type' => 'rabbitmq',
      'realservers' => realservers
    }]
  end
end
