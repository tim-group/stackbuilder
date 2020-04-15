require 'stackbuilder/stacks/namespace'

module Stacks::Dependencies
  ServiceDependency = Struct.new(:from, :to_selector) do
    def [](_)
      raise "Don't use this"
    end
  end

  EnvironmentDependency = Struct.new(:from, :to_selector) do
    def [](_)
      raise "Don't use this"
    end
  end

  ServiceSelector = Struct.new(:service_name, :env_name, :requirement) do
    def matches(thing)
      thing.is_a?(Stacks::MachineSet) && service_name.eql?(thing.name) && env_name.eql?(thing.environment.name)
    end
  end

  SiteSelector = Struct.new(:site, :requirement) do
  end

  public

  # FIXME: rpearce: This does not belong here but is needed to provide a mechanism for late binding through composition.
  def self.extended(object)
    object.configure
  end

  def config_params(_dependant, _fabric, _dependent_instance)
    {} # parameters for config.properties of apps depending on this service
  end

  def fqdn_list(instances, networks = [:prod])
    fqdns = []
    networks.each do |network|
      instances.map do |instance|
        fqdns << instance.qualified_hostname(network)
      end
    end
    fqdns.sort
  end

  def dependant_load_balancer_fqdns(location, networks = [:prod])
    instances = dependant_instances_of_type(Stacks::Services::LoadBalancer, location)
    fqdn_list(instances, networks)
  end

  def dependant_app_server_fqdns(location, networks = [:prod])
    instances = dependant_instances_of_type(Stacks::Services::AppServer, location)
    fqdn_list(instances, networks)
  end

  def dependant_instance_fqdns(location, networks = [:prod], reject_nodes_in_different_location = true, reject_k8s_nodes = false)
    fqdn_list(dependant_instances(location, reject_nodes_in_different_location, reject_k8s_nodes), networks).sort
  end

  def virtual_services_that_depend_on_me
    dependants.map(&:from).uniq
  end

  def dependencies
    dynamic_deps = (self.respond_to?(:establish_dependencies) ? establish_dependencies : []).map do |dep|
      ServiceDependency.new(self, ServiceSelector.new(dep[0], dep[1]))
    end

    @depends_on + dynamic_deps + environment.depends_on
  end

  # These are the dependencies from others onto this service
  def dependants
    @environment.calculated_dependencies.map(&:last).flatten.select do |dep|
      dep.to_selector.matches(self)
    end
  end

  def get_children_for_virtual_services(virtual_services,
                                        location = :primary_site,
                                        reject_nodes_in_different_location = true,
                                        reject_k8s_nodes = false)

    children = []
    virtual_services.map do |service|
      next if reject_k8s_nodes && service.kubernetes
      children.concat(service.children)
    end

    nodes = children.flatten

    if reject_nodes_in_different_location
      nodes.reject! { |node| node.location != location }

      if location == :secondary_site
        nodes.reject! { |node| node.virtual_service.secondary_site? == false }
      end
    end
    nodes
  end

  def virtual_services_that_i_depend_on(include_env_dependencies = true)
    dependencies.reject do |dep|
      dep.is_a?(Stacks::Dependencies::EnvironmentDependency) && !include_env_dependencies
    end.map do |depends_on|
      find_virtual_service_that_i_depend_on(depends_on)
    end
  end

  def dependant_instances_of_type(type, location)
    dependant_instances(location).reject { |machine_def| machine_def.class != type }
  end

  private

  def dependant_instances(location, reject_nodes_in_different_location = true, reject_k8s_nodes = false)
    get_children_for_virtual_services(
      virtual_services_that_depend_on_me,
      location,
      reject_nodes_in_different_location,
      reject_k8s_nodes)
  end

  def find_virtual_service_that_i_depend_on(dependency)
    virtual_service = @environment.lookup_dependency(dependency.to_selector)

    fail "Cannot find service #{dependency.to_selector.service_name} in #{dependency.to_selector.env_name}, that I depend_on" if virtual_service.nil?

    virtual_service
  end

  def requirements_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.select { |dependency| dependency.to_selector.matches(self) }
    dependent_on_this_cluster.map do |dependency|
      dependency.to_selector.requirement
    end
  end
end
