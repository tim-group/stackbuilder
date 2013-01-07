require 'stacks/namespace'
require 'stacks/virtual_service'
require 'stacks/server'

class Stacks::VirtualServiceDefinition
  attr_reader :name
  attr_accessor :times
  attr_reader :options
  attr_reader :machines

  def initialize(name, options)
    @name = name
    @options = options
    @times = 2
    @machines = {}
  end

  def generate(env)
    @times.times do |i|
      appservername = sprintf("%s-%s-%03d", env.name, self.name, i+1)
      appserver = machines[appservername] = Stacks::Server.new(appservername, self.name, env, self.options[:type])
    end
  end
end
