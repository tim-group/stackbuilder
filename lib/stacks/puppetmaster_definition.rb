require 'stacks/namespace'
require 'stacks/puppetmaster'
require 'stacks/server'

class Stacks::PuppetMasterDefinition
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def generate(env)
    registry = {}
    name = "#{env.name}-#{self.name}-001"
    registry[name] = Stacks::PuppetMaster.new(name, env)
    return registry
  end
end
