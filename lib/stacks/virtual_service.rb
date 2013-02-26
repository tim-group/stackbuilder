require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/server'

class Stacks::VirtualService < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name, env)
    @name = name
    @definitions = {}

    2.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] =  Stacks::Server.new(name, index, :primary)
    end
  end

  def clazz
    return 'virtualservice'
  end

end
