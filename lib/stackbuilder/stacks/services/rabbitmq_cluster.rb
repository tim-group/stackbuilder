require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMQCluster
  def self.extended(object)
    object.configure
  end

  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def configure
    @downstream_services = []
    @ports = [5672]
  end

  def clazz
    'rabbitmqcluster'
  end

  def cluster_nodes(location)
    realservers(location).map(&:prod_fqdn).sort.map do |fqdn|
      fqdn.split('.')[0]
    end
  end

  def to_loadbalancer_config(location, fabric)
    {
      vip_fqdn(:prod, fabric) => {
        'type' => 'rabbitmq',
        'ports' => @ports,
        'realservers' => {
          'blue' => realserver_prod_fqdns(location)
        }
      }
    }
  end
end
