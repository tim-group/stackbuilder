require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ExternalServer < Stacks::MachineDef
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

  def validate_name
  end

  def qualified_hostname(_network)
    @base_hostname
  end

  def to_enc
    enc = super
  end

  def to_spec
  end

  def needs_poll_signing?
    false
  end
end
