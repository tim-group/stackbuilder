require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::EventStoreServer < Stacks::MachineDef
  def to_enc
    enc = super()
    siblings = @virtual_service.children
    enc.merge!('role::eventstore_server' => {
                 'clusternodes'        => siblings.map(&:prod_fqdn).sort,
                 'dependant_instances' => @virtual_service.dependant_instance_fqdns(location, [:prod], false)
               })
    enc
  end
end
