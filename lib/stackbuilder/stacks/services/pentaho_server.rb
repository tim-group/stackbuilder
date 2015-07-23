require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::PentahoServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    @data_directory  = false
    super(virtual_service.name + "-" + index)
  end

  attr_accessor :application

  def to_enc
    enc = super()
    enc.merge! ({
      'role::pentaho_server' => {
        'datadir'     => @data_directory,
        'environment' => environment.name
      }
    })
    enc
  end
end
