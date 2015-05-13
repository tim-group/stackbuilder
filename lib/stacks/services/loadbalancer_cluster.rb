require 'stacks/namespace'

module Stacks::Services::LoadBalancerCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def establish_dependencies(location)
    services = virtual_services.select do |node|
      node.respond_to?(:to_loadbalancer_config) &&
      node.respond_to?(:load_balanced_service?)
    end
    @depends_on = services.map do |node|
      [node.name, environment.name, location]
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
        node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::LoadBalancer)
      )
    end
    lb_services.uniq.map do |node|
      if location == :primary_site
        config_hash.merge! node.to_loadbalancer_config(location)
      else
        if node.respond_to?(:secondary_site?)
          config_hash.merge! node.to_loadbalancer_config(location) if node.secondary_site?
        end
      end
    end

    config_hash
  end

  def clazz
    'loadbalancercluster'
  end
end
