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
  attr_reader :depends_on
  attr_accessor :auto_configure_dependencies

  include Stacks::MachineDefContainer

  def initialize(name, &config_block)
    @name = name
    @groups = ['blue']
    @definitions = {}
    @bind_steps = []
    @instances = 2
    @config_block = config_block
    @depends_on = []
    @auto_configure_dependencies = true
  end

  def depend_on(dependant, env=environment.name )
    @depends_on << [dependant,env] unless @depends_on.include? [dependant,env]
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

  def config_params(dependant)
    {} # parameters for config.properties of apps depending on this service
  end

  private
  def find_virtual_service(service, environments=[environment])
    environments.each do |env|
      env.accept do |machine_def|
        if machine_def.kind_of? Stacks::MachineSet and service.first.eql? machine_def.name and service[1].eql? env.name
          return machine_def
        end
      end
    end

    raise "Cannot find the service called #{service.first}"
  end


  private
  def resolve_virtual_services(dependencies, environments=[environment])
    dependencies.map do |dependency|
      find_virtual_service(dependency, environments)
    end
  end

  public
  def children_fqdn(networks=[:prod])
    children_fqdns = []
    networks.each do |network|
      children.map do |service|
        children_fqdns << service.qualified_hostname(network)
      end
    end
    children_fqdns
  end

  public
  def to_fqdn(machine_sets, networks=[:prod])
    fqdns = []
    networks.each do |network|
      machine_sets.map do |machine_set|
        machine_set.children.map do |machine_def|
          fqdns << machine_def.qualified_hostname(network)
        end
      end
    end
    fqdns
  end

  public
  def dependant_instances_including_children(networks=[:prod])
    dependant_instances(networks).concat(children_fqdn(networks))
  end

  public
  def dependant_instances_including_children_reject_type(type, networks=[:prod])
    dependant_instances(networks, reject_type(dependant_services, type)).concat(children_fqdn(networks)).sort
  end

  public
  def dependant_instances_including_children_reject_type_and_different_env(type, networks=[:prod])
    dependants = reject_type(dependant_services, type)
    dependants = reject_env(dependants, environment)
    dependant_instances(networks, dependants).concat(children_fqdn(networks)).sort
  end

  public
  def dependant_instances_accept_type(type, networks=[:prod])
    dependant_instances(networks, accept_type(dependant_services, type)).sort
  end

  public
  def reject_env(dependants, env)
    dependants.reject { |machine_def| machine_def.environment.name != env.name  }
  end

  public
  def reject_type(dependants, type)
    dependants.reject { |machine_def| machine_def.type == type }
  end

  public
  def accept_type(dependants, type)
    dependants.reject { |machine_def| machine_def.type != type }
  end

  public
  def reverse_this_shit
    my_depends_on = depends_on
    dependants = []
    environment.environments.each do |name, env|
      env.accept do |machine_def|
        if machine_def.kind_of? Stacks::MachineDefContainer and machine_def.respond_to? :depends_on and machine_def.name == my_depends_on[0] and machine_def.environment.name == my_depends_on[1]
          dependants.push machine_def
        end
      end
    end
    dependants
  end

  public
  def dependant_services
    dependants = []
    environment.environments.each do |name, env|
      env.accept do |machine_def|
        if machine_def.kind_of? Stacks::MachineDefContainer and machine_def.respond_to? :depends_on and machine_def.depends_on.include?([self.name, environment.name])
          dependants.push machine_def
        end
      end
    end
    dependants
  end

  public
  def dependant_instances(networks=[:prod], dependants=dependant_services)
    dependant_instance_fqdns = []
    networks.each do |network|
      dependant_instance_fqdns.concat(dependants.map do |service|
        service.children
      end.flatten.map do |instance|
        instance.qualified_hostname(network)
      end)
    end
    dependant_instance_fqdns.sort
  end

  public
  def dependency_config
    config = {}
    if @auto_configure_dependencies
      resolve_virtual_services(depends_on).each do |dependency|
        config.merge! dependency.config_params(self)
      end
    end
    config
  end
  public
  def dependency_zone_config(environments)
    resolve_virtual_services(depends_on, environments)
  end

end
