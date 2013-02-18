require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/server'

class Stacks::VirtualService < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name, env)
    @name = name
    @definitions = {}
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary]
    @domain = "#{@fabric}.net.local"
    2.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] =  Stacks::Server.new(self, index, :primary)
    end
    super(environment)
  end

  def clazz
    return 'virtualservice'
  end

  def vip_fqdn
    "#{@environment.name}-#{name}-vip.#{@domain}"
  end

end
