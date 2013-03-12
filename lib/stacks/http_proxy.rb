require 'stacks/namespace'

class Stacks::HttpProxy < Stacks::MachineDef
  attr_reader :virtualservice

  def initialize(base_hostname, virtualservice)
    super(base_hostname)
    @virtualservice = virtualservice
    @downstream_services = []
  end

  def bind_to(environment)
    super(environment)
  end

  def add(service)
    @downstream_services << service
  end

  def downstream_services
    services = []
    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::VirtualService
        services << machine_def if @downstream_services.include?(machine_def.name)
      end
    end
    return services
  end

  def to_enc
    service_resources = downstream_services().map do |service|
      {
        'vhosts' => [virtualservice.vip_front_fqdn],
        'balancer_members' => [service.vip_fqdn]
      }
    end
    {
      'role::httpproxy' => service_resources[0]
    }
  end
end
