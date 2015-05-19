require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::EventStoreServer < Stacks::MachineDef
  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
  end

  def to_enc
    {
      'role::eventstore_server' => {
        'clusternodes' => @virtual_service.children.map(&:prod_fqdn)
      }
    }
  end
end
