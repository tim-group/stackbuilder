require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::LoadBalancerCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def depends_on
    virtual_services(Stacks::AbstractVirtualService).map do |machine|
      [machine.name, environment.name]
    end
  end

  def virtual_services(type)
    virtual_services = []
    environment.accept do |node|
      unless node.environment.contains_node_of_type?(Stacks::LoadBalancer) && environment != node.environment
        virtual_services << node if node.kind_of? type
      end
    end
    virtual_services
  end

  def clazz
    'loadbalancercluster'
  end
end
