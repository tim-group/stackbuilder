require 'stacks/namespace'
require 'stacks/machine_def_container'

class Stacks::VirtualService
  attr_reader :name

  def initialize(name, env)
    extend Stacks::MachineDefContainer
    @name = name
    @definitions = {}

    2.times do |i|
      app_server_name = sprintf("%s-%s-%03d", env.name, name, i+1)
      @definitions[app_server_name] = Stacks::Server.new(app_server_name, name)
    end
  end

end
