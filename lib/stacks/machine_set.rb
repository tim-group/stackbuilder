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
    machine_defs_to_fqdns(children,network)
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
#    get_machine_defs_from_virtual_services(dependant_services,networks).concat(children_fqdn(networks))
    virtual_service_children = get_children_for_virtual_services(dependant_virtual_services)
    virtual_service_children.concat(children)
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  public
  def dependant_instances_including_children_reject_type(type, networks=[:prod])
    #get_machine_defs_from_virtual_services(reject_type(dependant_services, type),networks).concat(children_fqdn(networks)).sort

    virtual_service_children = get_children_for_virtual_services(dependant_virtual_services)
    virtual_service_children.concat(children)
    virtual_service_children.reject! { |machine_def| machine_def.class != type }
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  public
  def dependant_instances_including_children_reject_type_and_different_env(type, networks=[:prod])
    #dependants = reject_type(dependant_services, type)
    #dependants = reject_env(dependants, environment)

    #get_machine_defs_from_virtual_services(dependants,networks).concat(children_fqdn(networks)).sort

    virtual_service_children = get_children_for_virtual_services(dependant_virtual_services)
    virtual_service_children.concat(children)
    virtual_service_children.reject! { |machine_def| machine_def.class != type }
    virtual_service_children.reject! { |machine_def| machine_def.environment.name == environment.name }
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  public
  def dependant_instances_accept_type(type, networks=[:prod])
    #get_machine_defs_from_virtual_services(accept_type(dependant_virtual_services, type),networks).sort
    virtual_service_children = get_children_for_virtual_services(dependant_virtual_services)
    virtual_service_children.reject! { |machine_def| machine_def.class != type }
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  public
  def dependant_load_balancer_machine_defs
    virtual_service_children = get_children_for_virtual_services(dependant_virtual_services)
    virtual_service_children.reject! { |machine_def| machine_def.class != Stacks::LoadBalancer }
    virtual_service_children
  end

  def dependant_load_balancer_machine_def_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_load_balancer_machine_defs, networks).sort
  end

  public
  def dependant_machine_defs
    get_children_for_virtual_services(dependant_virtual_services)
  end

  def dependant_machine_defs_with_children
    dependant_machine_defs.concat(children)
  end

  def dependant_machine_def_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_machine_defs, networks).sort
  end

  def dependant_machine_def_with_children_fqdns(networks=[:prod])
    machine_defs_to_fqdns(dependant_machine_defs_with_children, networks).sort
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
  def virtual_services
    virtual_services = []
    environment.environments.each do |name, env|
      env.accept do |virtual_service|
        virtual_services.push virtual_service
      end
    end
    virtual_services
  end

  public
  def dependant_virtual_services
    dependant_virtual_services = []
    virtual_services.each do |virtual_service|
      if virtual_service.kind_of? Stacks::MachineDefContainer and virtual_service.respond_to? :depends_on and virtual_service.depends_on.include?([self.name, environment.name])
        dependant_virtual_services.push virtual_service
      end
    end
    dependant_virtual_services
  end

  public
  def get_machine_defs_from_virtual_services(virtual_services, networks=[:prod])
    virtual_service_children = get_children_for_virtual_services(virtual_services)
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  public
  def get_children_for_virtual_services(virtual_services)
    children = []
    virtual_services.map do |service|
      children.concat(service.children)
    end
    children.flatten
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
  # FIXME: rename this, it's like reverse dependencies nothing to do with zone config
  def dependency_zone_config(environments)
    resolve_virtual_services(depends_on, environments)
  end

end
