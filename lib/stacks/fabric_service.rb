require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/server'

class Stacks::FabricService < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name, env)
    @name = name
    @definitions = {}

    1.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] =  Stacks::Server.new(name, index, :primary, 'fabricapply')
    end
  end

  def clazz
    return 'fabricservice'
  end

  def rspecs
    return ['end2end']
  end

end
