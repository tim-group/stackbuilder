require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::StandaloneServer < Stacks::MachineDef
  attr_reader :environment

  def initialize(base_hostname, location, &block)
    super(base_hostname)
    block.call unless block.nil?
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super()
    spec.delete(:availability_group)
    spec
  end
end
