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
    zones = nil
    @virtual_service.dependency_zone_config(environment.environments.values).each do |serv|
      serv.children.each do |child_machine_def|
        if child_machine_def.kind_of? Stacks::BindServer and child_machine_def.master?
          zones = {} if zones.nil?
          zones[child_machine_def.mgmt_fqdn] = child_machine_def.virtual_service.master_zones_fqdn
        end
      end
    end
    zones
  end

  public
  def to_enc()
    enc = super()
    enc.merge!({
      'role::bind_server' => {
        'vip_fqdns'           => [ vip_fqdn(:prod), vip_fqdn(:mgmt)],
        'participation_dependant_instances' => @virtual_service.dependant_load_balancer_machine_def_fqdns([:mgmt,:prod])
      },
      'server::default_new_mgmt_net_local' => nil,
    })
    enc['role::bind_server']['master_zones'] = @virtual_service.master_zones_fqdn if master?
    enc['role::bind_server']['slave_zones'] = @virtual_service.slave_zones_fqdn(self)
    if enc['role::bind_server']['slave_zones'].nil?
      enc['role::bind_server']['slave_zones'] = dependant_zones
    else
      enc['role::bind_server']['slave_zones'].merge! dependant_zones unless dependant_zones.nil?
    end

    enc['role::bind_server']['dependant_instances'] = @virtual_service.all_dependencies(self)

    enc['role::bind_server']['forwarder_zones'] = @virtual_service.forwarder_zones
    enc
  end
end
