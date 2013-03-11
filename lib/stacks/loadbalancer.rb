require 'stacks/namespace'

class Stacks::LoadBalancer < Stacks::MachineDef

  attr_accessor :virtual_router_id

  def bind_to(environment)
    super(environment)
    @virtual_router_id = environment.options[:virtual_router_id]
  end

  def virtual_services
    virtual_services = []
    environment.accept do |node|
      unless node.environment.contains_node_of_type?(Stacks::LoadBalancer) && environment != node.environment
        virtual_services << node if node.kind_of? ::Stacks::VirtualService
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
    virtual_services_array = virtual_services.map do |virtual_service|
       grouped_realservers = virtual_service.realservers.group_by do |realserver|
        realserver.group
       end

       realservers = Hash[grouped_realservers.map do |group, realservers|
         realserver_fqdns = realservers.map do |realserver|
          realserver.prod_fqdn
         end.sort
         [group, realserver_fqdns]
       end]

      [virtual_service.vip_fqdn, {
        'env' => virtual_service.environment.name,
        'app' => virtual_service.application,
        'realservers' => realservers
      }]
    end

    {
      'role::loadbalancer'=> {
        'virtual_servers' => Hash[virtual_services_array]
      }
    }
  end
end
