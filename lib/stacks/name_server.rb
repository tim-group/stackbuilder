require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::NameServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service

  def initialize(virtual_service, index, &block)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  public
  def to_enc()
    enc = {
      'role::ns_server' => nil,
      'server::default_new_mgmt_net_local' => nil,
    }
    enc
  end
end
