require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::EventStoreServer < Stacks::MachineDef

  def to_enc
    enc = super()
    siblings = @virtual_service.children.select { |child| child != self }
    enc.merge!('role::eventstore_server' => {
                 'clusternodes' => siblings.map(&:prod_fqdn).sort
               })
    enc
  end
end
