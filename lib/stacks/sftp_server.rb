require 'stacks/namespace'

class Stacks::SftpServer < Stacks::MachineDef
  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def vip_fqdn(net)
    @virtual_service.vip_fqdn(net)
  end

  def to_enc
    enc = super
    enc.merge!('role::sftpserver' => {
                 'vip_fqdn' => vip_fqdn(:prod),
                 'env' => environment.name,
                 'participation_dependant_instances' => @virtual_service.dependant_load_balancer_machine_def_fqdns([:prod])
               })
    enc
  end
end
