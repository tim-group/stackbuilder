require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

class Stacks::MachineSet
  attr_accessor :type
  attr_accessor :name
  attr_accessor :fabric
  attr_accessor :instances
  attr_accessor :ports
  attr_accessor :port_map
  attr_accessor :groups
  attr_accessor :depends_on

  include Stacks::MachineDefContainer

  def initialize(name, &config_block)
    @name = name
    @groups = ['blue']
    @definitions = {}
    @bind_steps = []
    @instances = 2
    @config_block = config_block
    @depends_on = []
  end

  def on_bind(&block)
    @bind_steps << block
  end

  def bind_to(environment)
    @bind_steps.each do |step|
      step.call(self, environment)
    end
  end

  def each_machine(&block)
    on_bind do
      accept do |machine|
        block.call(machine) if machine.kind_of? Stacks::MachineDef
      end
    end
  end

  def config_params
    [] # parameters for config.properties of apps depending on this service
  end

  private
  def find_virtual_service(service)
    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::MachineSet and service.eql? machine_def.name
        return machine_def
      end
    end

    raise "Cannot find the service called #{service}"
  end


  private
  def resolve_virtual_services(dependencies)
    dependencies.map do |dependency|
      find_virtual_service(dependency)
    end
  end

  private
  def dependant_services
    dependants = []
    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::MachineDefContainer and machine_def.respond_to? :depends_on and machine_def.depends_on.include?(self.name)
        dependants.push machine_def
      end
    end
    dependants
  end

  public
  def dependant_instances
    (dependant_services.map do |service|
      service.children
    end.flatten.map do |instance|
      instance.prod_fqdn
    end).sort
  end
  
  public
  def dependency_config
    (Hash[resolve_virtual_services(depends_on).inject([]) do |acc, dependency|
      acc + dependency.config_params
     end]).sort_by { |key, value| key }
  end
end
