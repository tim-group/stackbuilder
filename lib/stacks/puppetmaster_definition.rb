require 'stacks/namespace'
require 'stacks/puppetmaster'
require 'stacks/server'

class Stacks::PuppetMasterDefinition
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def generate(env)
    name = "#{env.name}-#{self.name}-001"
    return {name=>Stacks::PuppetMaster.new(name, env)}
  end
end
