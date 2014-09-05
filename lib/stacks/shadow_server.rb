require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::ShadowServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service
  attr_accessor :group, :hostname, :domain, :name

  def initialize(virtual_service, index, &block)
    super(virtual_service.name)
    @virtual_service = virtual_service
    @storage = {}
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
   {}
  end

  def to_spec
  end

  def needs_poll_signing?
    false
  end

end
