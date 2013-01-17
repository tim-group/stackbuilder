require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server  < Stacks::MachineDef
  attr_reader :server_type

  def initialize(virtual_group, index, location)
    @virtual_group = virtual_group
    @index = index
    @location = location
  end

  def bind_to(environment)
    @hostname = environment.name + "-" + @virtual_group + "-" + @index
    @fabric = environment.options[@location]
    @domain = "#{@fabric}.net.local"
    @availability_group = environment.name + "-" + @virtual_group
  end

  def fqdn
    return "#{@hostname}.#{@domain}"
  end

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :group => @availability_group,
      :template => 'copyboot'
    }]
  end
end
