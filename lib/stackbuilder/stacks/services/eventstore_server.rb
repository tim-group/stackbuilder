require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::EventStoreServer < Stacks::MachineDef
  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
  end

  def to_enc
    enc = super()
    siblings = @virtual_service.children.select { |child| child != self }
    enc.merge!('role::eventstore_server' => {
                 'clusternodes' => siblings.map(&:prod_fqdn).sort
               })
    enc
  end
end
