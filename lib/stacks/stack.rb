require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/fabric_service'

class Stacks::Stack < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtualservice(name)
    @definitions[name] = Stacks::VirtualService.new(name, self)
  end

  def fabricservice(name)
    @definitions[name] = Stacks::FabricService.new(name, self)
  end

  def [](key)
    return @definitions[key]
  end

end
