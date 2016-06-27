require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::StandardServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def allowed_hosts_enc
    return {} if @virtual_service.allowed_hosts.empty?
    {
      'allowed_hosts' => @virtual_service.allowed_hosts
    }
  end

  def to_enc
    enc = super
    enc.merge!(allowed_hosts_enc)
    enc.merge!('server::default_new_mgmt_net_local' => {})
    enc
  end
end
