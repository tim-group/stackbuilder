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


  public
  def machine_defs_to_fqdns(machine_defs, networks=[:prod])
    fqdns = []
    networks.each do |network|
      machine_defs.map do |machine_def|
        fqdns << machine_def.qualified_hostname(network)
      end
    end
    fqdns
  end

  public
  def dependant_load_balancer_machine_defs
    virtual_service_children = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    virtual_service_children.reject! { |machine_def| machine_def.class != Stacks::LoadBalancer }
    virtual_service_children
  end

  public
  def dependant_load_balancer_machine_def_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_load_balancer_machine_defs, networks).sort
  end

  public
  def dependant_machine_defs
    get_children_for_virtual_services(virtual_services_that_depend_on_me)
  end

  public
  def dependant_machine_def_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_machine_defs, networks).sort
  end

  public
  def dependant_machine_defs_with_children
    dependant_machine_defs.concat(children)
  end

  public
  def dependant_machine_def_with_children_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_machine_defs_with_children, networks).sort
  end

  public
  def virtual_services(environments=environment.environments)
    virtual_services = []
    environment.environments.each do |name, env|
      env.accept do |virtual_service|
        virtual_services.push virtual_service
      end
    end
    virtual_services
  end

  public
  def virtual_services_that_depend_on_me
    virtual_services_that_depend_on_me = []
    virtual_services.each do |virtual_service|
      if virtual_service.kind_of? Stacks::MachineDefContainer and virtual_service.respond_to? :depends_on and virtual_service.depends_on.include?([self.name, environment.name])
        virtual_services_that_depend_on_me.push virtual_service
      end
    end
    virtual_services_that_depend_on_me
  end

  private
  def find_virtual_service_that_i_depend_on(service, environments=[environment])
    environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.kind_of? Stacks::MachineSet and service[0].eql? virtual_service.name and service[1].eql? env.name
          return virtual_service
        end
      end
    end
    raise "Cannot find service #{depend_on[0]} in #{depend_on[1]}, that I depend_on"
  end


  public
  def get_children_for_virtual_services(virtual_services)
    children = []
    virtual_services.map do |service|
      children.concat(service.children)
    end
    children.flatten
  end

  private #resolve_virtual_services
  def virtual_services_that_i_depend_on(dependencies, environments=[environment])
    dependencies.map do |dependency|
      find_virtual_service_that_i_depend_on(dependency, environments)
    end
  end

  public
  def dependency_config
    config = {}
    if @auto_configure_dependencies
      virtual_services_that_i_depend_on(depends_on).each do |dependency|
        config.merge! dependency.config_params(self)
      end
    end
    config
  end




end
