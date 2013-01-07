require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server  < Stacks::MachineDef
  attr_reader :server_type
  attr_reader :application_name
  attr_accessor :dependencies

  def initialize(name, application_name)
    super(name)
    @application_name = application_name
  end

  def to_spec
    spec = super

    return spec
  end
end
