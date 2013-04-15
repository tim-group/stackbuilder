require 'stacks/namespace'

class Stacks::SftpServer < Stacks::MachineDef
  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    {
      'role::sftpserver' => {
      }
    }
  end
end
