require 'stacks/namespace'

module Stacks::Services::LoadBalancerCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def depends_on
    virtual_services(Stacks::Services::AbstractVirtualService).map do |machine|
      [machine.name, environment.name]
    end
  end

  def virtual_services(type)
    virtual_services = []
    environment.accept do |node|
      unless node.environment.contains_node_of_type?(Stacks::Services::LoadBalancer) && environment != node.environment
        virtual_services << node if node.is_a? type
      end
    end
    virtual_services
  end

  def clazz
    'loadbalancercluster'
  end
end
