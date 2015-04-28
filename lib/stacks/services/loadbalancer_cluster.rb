require 'stacks/namespace'

module Stacks::Services::LoadBalancerCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def depends_on
    services = virtual_services.select { |node| node.respond_to?(:to_loadbalancer_config) }
    services.map do |node|
      [node.name, environment.name]
    end
  end

  def loadbalancer_config_hash(location)
    config_hash = {}
    services = virtual_services.select do |node|
      node.respond_to?(:to_loadbalancer_config)
    end

    lb_services = services.select do |node|
      node.environment == environment ||
      (
        node.environment.parent == environment  &&
        !node.environment.contains_node_of_type?(Stacks::Services::LoadBalancer)
      )
    end

    lb_services.uniq.map do |node|
      config_hash.merge! node.to_loadbalancer_config(location)
    end
    config_hash
  end

  def clazz
    'loadbalancercluster'
  end
end
