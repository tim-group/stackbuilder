require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::KafkaServer < Stacks::MachineDef
  def to_enc
    enc = super()
    siblings = @virtual_service.children
    enc.merge!('role::kafka_server' => {
                 'hostname'            => @hostname,
                 'clusternodes'        => siblings.map(&:prod_fqdn).sort,
                 'dependant_instances' => @virtual_service.dependant_instance_fqdns(location, [:prod], false)
               })
    enc
  end
end
