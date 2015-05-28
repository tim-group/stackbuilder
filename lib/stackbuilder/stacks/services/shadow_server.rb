require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::ShadowServer < Stacks::MachineDef
  attr_reader :environment, :virtual_service
  attr_accessor :group, :hostname, :domain

  def initialize(virtual_service, _index)
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
