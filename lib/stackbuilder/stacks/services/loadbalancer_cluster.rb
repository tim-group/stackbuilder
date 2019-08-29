require 'stackbuilder/stacks/namespace'

module Stacks::Services::LoadBalancerCluster
  attr_accessor :extra_virtual_services

  def self.extended(object)
    object.configure
  end

  def configure
    @extra_virtual_services = {}
  end

  def establish_dependencies
    services = []
    @environment.accept do |thing|
      if thing.respond_to?(:to_loadbalancer_config) &&
         thing.respond_to?(:load_balanced_service?) &&
         thing.load_balanced_service?
        services << [thing.name, thing.environment.name]
      end
    end
    services
  end

  def loadbalancer_config_hash(location, fabric)
    config_hash = @extra_virtual_services.dup
    services = @environment.all_things.select do |thing|
      thing.respond_to?(:to_loadbalancer_config)
    end

    lb_services = services.select do |node|
      node.environment == environment ||
      (
        node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::LoadBalancer)
      )
    end
    lb_services.uniq.map do |node|
      node_lb_config = node.to_loadbalancer_config(location, fabric)
      config_hash.merge! node_lb_config
    end
    reject_vips_without_realservers config_hash
  end

  def clazz
    'loadbalancercluster'
  end

  def hack_in_virtual_service(service_hash)
    @extra_virtual_services.merge! service_hash
  end

  private

  def reject_vips_without_realservers(lb_config)
    lb_config.reject { |_vip, config| !config.key?('realservers') || config['realservers'].empty? }
  end
end
