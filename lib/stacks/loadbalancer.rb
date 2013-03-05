require 'stacks/namespace'

class Stacks::LoadBalancer < Stacks::MachineDef
  def bind_to(environment)
    @environment = environment
    @hostname = environment.name + "-" + @hostname
    @fabric = environment.options[:primary]
    @domain = "#{@fabric}.net.local"
    @networks = [:mgmt, :prod]
    raise "domain must not contain mgmt" if @domain =~ /mgmt\./
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

  def to_enc
    virtual_services_array = virtual_services.map do |virtual_service|
      realservers = virtual_service.realservers.map do |realserver|
        realserver.prod_fqdn
      end

      realservers = realservers.sort

      [virtual_service.vip_fqdn, {
        'env' => virtual_service.environment.name,
        'app' => 'JavaHttpRef',
        'realservers' => {
          'blue' => realservers
        }
      }]
    end

    {
      'role::loadbalancer'=> {
        'virtual_servers' => Hash[virtual_services_array]
      }
    }
  end
end
