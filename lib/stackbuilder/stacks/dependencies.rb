require 'stackbuilder/stacks/namespace'

module Stacks::Dependencies
  public

  DependencyId = Struct.new(:name, :environment_name)

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
    virtual_services_that_depend_on_me = []
    @environment.calculated_dependencies.each do |virtual_service, depends_on|
      next if !depends_on.any? { |depend| depend[0] == name && depend[1] == environment.name }

      virtual_services_that_depend_on_me.push virtual_service
    end

    virtual_services_that_depend_on_me.uniq
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
    dependencies = @depends_on
    dependencies += environment.depends_on if include_env_dependencies
    dependencies.map do |depends_on|
      find_virtual_service_that_i_depend_on(DependencyId.new(depends_on[0], depends_on[1]))
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

  def find_virtual_service_that_i_depend_on(dependency_id)
    virtual_service = @environment.lookup_dependency(dependency_id)

    fail "Cannot find service #{dependency_id[0]} in #{dependency_id[1]}, that I depend_on" if virtual_service.nil?

    virtual_service
  end

  def requirements_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.select { |dependency| dependency[0] == name && dependency[1] == environment.name }
    dependent_on_this_cluster.inject([]) do |requirements, dependency|
      requirements << dependency[2]
    end
  end
end
