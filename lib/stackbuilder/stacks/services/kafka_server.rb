require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::KafkaServer < Stacks::MachineDef
  def to_enc
    enc = super()
    siblings = @virtual_service.children.select { |child| child != self }
    enc.merge!('role::kafka_server' => {
                 'clusternodes'        => siblings.map(&:prod_fqdn).sort,
                 'dependant_instances' => @virtual_service.dependant_instance_fqdns(location, [:prod], false)
               })
    enc
  end
end
