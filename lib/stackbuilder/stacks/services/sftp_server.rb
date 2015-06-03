require 'stackbuilder/stacks/namespace'

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
                   @virtual_service.dependant_load_balancer_fqdns(location, [:prod]),
                 'ssh_dependant_instances' =>
                   @virtual_service.dependant_app_server_fqdns(location, [:mgmt])
               })
    enc
  end
end