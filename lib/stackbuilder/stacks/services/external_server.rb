require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ExternalServer < Stacks::MachineDef
  attr_reader :environment, :virtual_service
  attr_accessor :group, :hostname, :domain

  def validate_name
  end

  def qualified_hostname(_network)
    @base_hostname
  end

  def to_enc
    {}
  end

  def to_spec
    {}
  end

  def needs_poll_signing?
    false
  end
end
