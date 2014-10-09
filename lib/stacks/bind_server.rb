require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::BindServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service

  def initialize(base_hostname, virtual_service, role, index, &block)
    @role = role
    super(base_hostname, [:mgmt,:prod], :primary_site)
    @zones = [:mgmt, :prod, :front]
    @virtual_service = virtual_service
  end

  def role
    @role
  end

  def zones
    @zones
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

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def zones_fqdn
    return zones.inject([]) do |zones, zone|
      if zone.eql?(:prod)
        zones << "#{@domain}"
      else
        zones << "#{zone.to_s}.#{@domain}"
      end
      zones
    end
  end

  public
  def to_enc()
    enc = {
      'role::bind_server' => {
        'role'         => @role,
        'zones'        => zones_fqdn
      },
      'server::default_new_mgmt_net_local' => nil,
    }
    enc['role::bind_server']['slaves_fqdn'] = @virtual_service.slave_servers if master?
    enc['role::bind_server']['master_fqdn'] = @virtual_service.master_server if slave?
    enc
  end
end
