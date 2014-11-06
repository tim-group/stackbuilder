require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::BindServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service

  def initialize(base_hostname, virtual_service, role, index, &block)
    @role = role
    super(base_hostname, [:mgmt,:prod], :primary_site)
    @virtual_service = virtual_service
  end

  def role
    @role
  end

  def master?
    @role == :master
  end

  def slave?
    @role == :slave
  end

  def bind_to(environment)
    super(environment)
  end

  def vip_fqdn(net)
    return @virtual_service.vip_fqdn(net)
  end

  def zones_fqdn
    @virtual_service.zones_fqdn
  end

  def slave_from(env)
    @virtual_service.depend_on('ns', env)
  end

  def dependant_zones
#    environment.environments.each do |name,env|
#      env.accept do |machine_def|
#        if machine_def.kind_of? Stacks::BindServer and machine.master?
#        end
#      end
#    end
#    @virtual_service.dependant_services.each do |serv|
#      puts "#{serv.class.ancestors.join(',')}"
#    end
  end

  public
  def to_enc()
    #dependant_zones
    enc = super()
    enc.merge!({
      'role::bind_server' => {
        'vip_fqdns'           => [ vip_fqdn(:prod), vip_fqdn(:mgmt)],
        'participation_dependant_instances' => @virtual_service.dependant_instances_accept_type(Stacks::LoadBalancer, [:mgmt,:prod])
      },
      'server::default_new_mgmt_net_local' => nil,
    })
    enc['role::bind_server']['master_zones'] = @virtual_service.master_zones_fqdn if master?
    enc['role::bind_server']['slave_zones'] = @virtual_service.slave_zones_fqdn if slave?


    enc['role::bind_server']['dependant_instances'] = @virtual_service.dependant_instances_including_children_reject_type(Stacks::LoadBalancer, [:mgmt]) if master?

    enc['role::bind_server']['dependant_instances'] = @virtual_service.dependant_instances_including_children_reject_type_and_different_env(Stacks::LoadBalancer, [:mgmt]) if slave?

    enc['role::bind_server']['forwarder_zones'] = @virtual_service.forwarder_zones
    enc
  end
end
