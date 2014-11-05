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

  def slave_from(env)
    @virtual_service.depend_on('ns', env)
  end

  def dependant_zones
    environment.environments.each do |name,env|
      env.accept do |machine_def|
        if machine_def.kind_of? Stacks::BindServer and machine.master?
        end
      end
    end
#    @virtual_service.dependant_services.each do |serv|
#      puts "#{serv.class.ancestors.join(',')}"
#    end
  end

  public
  def to_enc()
    dependant_zones
    enc = super()
    enc.merge!({
      'role::bind_server' => {
        'role'                => @role.to_s,
        'site'                => @fabric,
        'zones'               => @virtual_service.zones_fqdn,
        'vip_fqdns'           => [ vip_fqdn(:prod), vip_fqdn(:mgmt)],
        'dependant_instances' => @virtual_service.dependant_instances_including_children([:prod,:mgmt])
      },
      'server::default_new_mgmt_net_local' => nil,
    })
    enc['role::bind_server']['master_fqdn'] = @virtual_service.master_server
    enc['role::bind_server']['slaves_fqdn'] = @virtual_service.slave_servers
    enc['role::bind_server']['forwarder_zones'] = @virtual_service.forwarder_zones
    enc
  end
end
