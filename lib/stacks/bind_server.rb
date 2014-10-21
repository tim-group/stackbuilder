require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::BindServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service

  def initialize(base_hostname, virtual_service, role, index, &block)
    @role = role
    super(base_hostname, [:mgmt,:prod], :primary_site)
    @zones = [:mgmt, :prod, :front]
    @forwarder_zones = []
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

  def vip_fqdn(net)
    return @virtual_service.vip_fqdn(net)
  end

  def forwarder_zone(fwdr_zone)
    if fwdr_zone.kind_of?(Array)
      @forwarder_zones = @forwarder_zones + fwdr_zone
    else
      @forwarder_zones << fwdr_zone
    end
    @forwarder_zones.uniq!
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
    enc = super()
    enc.merge!({
      'role::bind_server' => {
        'role'         => @role.to_s,
        'zones'        => zones_fqdn,
        'vip_fqdns'    => [ vip_fqdn(:prod), vip_fqdn(:mgmt)]
      },
      'server::default_new_mgmt_net_local' => nil,
    })
    enc['role::bind_server']['master_fqdn'] = @virtual_service.master_server
    enc['role::bind_server']['slaves_fqdn'] = @virtual_service.slave_servers
    enc['role::bind_server']['forwarder_zones'] = @forwarder_zones
    enc
  end
end
