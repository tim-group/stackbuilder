require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MongoDBServer < Stacks::MachineDef
  attr_accessor :backup
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
    @backup = false
  end

  def to_enc
    enc = {
      'role::mongodb_server' => {
        'application' => @virtual_service.application
      },
      'mongodb::users' => {
        'environment' => environment.name
      }
    }
    enc['mongodb::backup'] = { 'ensure' => 'present' } if @backup
    enc
  end
end
