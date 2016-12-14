require 'stackbuilder/stacks/namespace'

module Stacks::Services::LoadBalancerCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def establish_dependencies
    services = @environment.virtual_services.select do |node|
      node.respond_to?(:to_loadbalancer_config) &&
      node.respond_to?(:load_balanced_service?) &&
      node.load_balanced_service?
    end
    services.map do |node|
      [node.name, environment.name]
    end
  end

  def loadbalancer_config_hash(location, fabric)
    config_hash = {}
    services = @environment.virtual_services.select do |node|
      node.respond_to?(:to_loadbalancer_config)
    end

    lb_services = services.select do |node|
      node.environment == environment ||
      (
        node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::LoadBalancer)
      )
    end
    lb_services.uniq.map do |node|
      config_hash.merge! node.to_loadbalancer_config(location, fabric)
    end
    config_hash
  end

  def clazz
    'loadbalancercluster'
  end
end
