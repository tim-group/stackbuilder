require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::AppServer < Stacks::MachineDef
  attr_reader :environment, :virtual_service
  attr_accessor :group

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

  def to_enc()
    enc = {
      'role::http_app' => {
        'application' => virtual_service.application,
        'group' => group,
       'environment' => environment.name
    }}

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn
    end
    enc
  end
end