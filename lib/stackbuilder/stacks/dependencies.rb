require 'securerandom'
require 'stackbuilder/stacks/namespace'

module Stacks::Dependencies
  public

  def config_params(_dependant, _fabric)
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

  def dependant_instance_fqdns(location, networks = [:prod], reject_nodes_in_different_location = true)
    fqdn_list(dependant_instances(location, reject_nodes_in_different_location), networks).sort
  end

  def dependant_instances_of_type(type, location)
    dependant_instances(location).reject { |machine_def| machine_def.class != type }
  end

  def dependant_instances(location, reject_nodes_in_different_location = true)
    get_children_for_virtual_services(
      virtual_services_that_depend_on_me,
      location,
      reject_nodes_in_different_location)
  end

  def virtual_services(environments = environment.find_all_environments)
    environment.virtual_services(environments)
  end

  def virtual_services_that_depend_on_me
    virtual_services_that_depend_on_me = []
    environment.calculated_dependencies.each do |virtual_service, depends_on|
      next if !depends_on.any? { |depend| depend[0] == name && depend[1] == environment.name }

      virtual_services_that_depend_on_me.push virtual_service
    end

    virtual_services_that_depend_on_me.uniq
  end

  def get_children_for_virtual_services(virtual_services,
                                        location = :primary_site,
                                        reject_nodes_in_different_location = true)
    children = []
    virtual_services.map do |service|
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

  def virtual_services_that_i_depend_on(environments = environment.find_all_environments)
    depends_on.map do |dependency|
      find_virtual_service_that_i_depend_on(dependency, environments)
    end
  end

  def find_environment(environment_name)
    env = environment.find_all_environments.select do |environment|
      environment.name == environment_name
    end
    if env.size == 1
      return env.first
    else
      fail "Cannot find environment '#{environment_name}'"
    end
  end

  private

  def find_virtual_service_that_i_depend_on(service, environments = [environment])
    environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.is_a?(Stacks::MachineSet) &&
           service[0].eql?(virtual_service.name) &&
           service[1].eql?(virtual_service.environment.name)
          return virtual_service
        end
      end
    end
    fail "Cannot find service #{service[0]} in #{service[1]}, that I depend_on"
  end
end
