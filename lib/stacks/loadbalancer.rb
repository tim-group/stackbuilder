require 'stacks/namespace'

class Stacks::LoadBalancer < Stacks::MachineDef

  attr_accessor :virtual_router_id

  def bind_to(environment)
    super(environment)
    @virtual_router_id = environment.options[:lb_virtual_router_id] || 1
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

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }]
  end

  def to_enc
    virtual_services_array = virtual_services(Stacks::VirtualService).map do |virtual_service|
        virtual_service.to_loadbalancer_config
    end
    {
      'role::loadbalancer'=> {
        'virtual_router_id' => self.virtual_router_id,
        'virtual_servers' => Hash[virtual_services_array]
      }
    }
  end
end
