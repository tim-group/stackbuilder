require 'stacks/namespace'

class Stacks::Services::SftpServer < Stacks::MachineDef
  attr_reader :location
  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def to_enc
    enc = super
    enc.merge!('role::sftpserver' => {
                 'vip_fqdn' => @virtual_service.vip_fqdn(:prod, location),
                 'env' => environment.name,
                 'participation_dependant_instances' =>
                   @virtual_service.dependant_load_balancer_machine_def_fqdns([:prod]),
                 'ssh_dependant_instances' =>
                   @virtual_service.ssh_dependant_instances_fqdns([:mgmt])
               })
    enc
  end
end