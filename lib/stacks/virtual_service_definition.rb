require 'stacks/namespace'
require 'stacks/virtual_service'
require 'stacks/server'

class Stacks::VirtualServiceDefinition
  attr_reader :name
  attr_accessor :times
  attr_reader :options
  attr_accessor :dependencies

  def initialize(name, options)
    @name = name
    @options = options
    @times = 2
  end

  def generate(env)
    registry = {}
    registry[self.name] = Stacks::VirtualService.new(self.name, env.name)
    registry[self.name].domain=env.domain

    @times.times do |i|
      appservername = sprintf("%s-%s-%03d", env.name, self.name, i+1)
      appserver = registry[appservername] = Stacks::Server.new(appservername, self.name, env, self.options[:type])

      if (not dependencies.nil?)
        resolved_dependencies = dependencies.map do |dependency| env.lookup(dependency) end
        appserver.dependencies = resolved_dependencies
      end

    end
    return registry
  end
end
