require 'securerandom'
require 'stacks/namespace'

module Stacks::Dependencies
  public

  def config_params(_dependant)
    {} # parameters for config.properties of apps depending on this service
  end

  def machine_defs_to_fqdns(machine_defs, networks = [:prod])
    fqdns = []
    networks.each do |network|
      machine_defs.map do |machine_def|
        fqdns << machine_def.qualified_hostname(network)
      end
    end
    fqdns
  end

  def dependant_load_balancer_machine_def_fqdns(networks = [:prod])
    virtual_service_children = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    virtual_service_children.reject! { |machine_def| machine_def.class != Stacks::Services::LoadBalancer }
    machine_defs_to_fqdns(virtual_service_children, networks).sort
  end

  def dependant_machine_defs
    get_children_for_virtual_services(virtual_services_that_depend_on_me)
  end

  def dependant_machine_def_fqdns(networks = [:prod])
    machine_defs_to_fqdns(dependant_machine_defs, networks).sort
  end

  def dependant_machine_def_with_children_fqdns(networks = [:prod])
    machine_defs_to_fqdns(dependant_machine_defs.concat(children), networks).sort
  end

  def virtual_services(environments = find_all_environments)
    virtual_services = []
    environments.each do |env|
      env.accept do |virtual_service|
        virtual_services.push virtual_service
      end
    end
    virtual_services
  end

  # the @@eligible_virtual_services_cache variable is used for caching a semi-processed list.
  # this reduces runs of sbx:dump_enc from 4-5 minutes to under 4 seconds (as of 24.04.2015)
  # rubocop:disable Style/ClassVars
  def virtual_services_that_depend_on_me
    # the constant part (cache)
    # do not cache if running from inside rspec, as virtual_services change there and it causes tests to fail
    if !defined?(@@eligible_virtual_services_cache) || ENV['INSIDE_RSPEC']
      @@eligible_virtual_services_cache = []
      virtual_services.each do |virtual_service|
        next if !virtual_service.is_a?(Stacks::MachineDefContainer)
        next if !virtual_service.respond_to?(:depends_on)

        @@eligible_virtual_services_cache.push [virtual_service, virtual_service.depends_on]
      end
    end

    # the variable part
    virtual_services_that_depend_on_me = []
    @@eligible_virtual_services_cache.each do |virtual_service, depends_on|
      next if !depends_on.include?([name, environment.name])

      virtual_services_that_depend_on_me.push virtual_service
    end
    virtual_services_that_depend_on_me.uniq
  end
  # rubocop:enable Style/ClassVars

  def get_children_for_virtual_services(virtual_services)
    children = []
    virtual_services.map do |service|
      children.concat(service.children)
    end
    children.flatten
  end

  def virtual_services_that_i_depend_on(environments = find_all_environments)
    depends_on.map do |dependency|
      find_virtual_service_that_i_depend_on(dependency, environments)
    end
  end

  private

  def find_all_environments(environments = environment.environments.values)
    environment_set = Set.new
    environments.each do |env|
      unless environment_set.include? env
        environment_set.merge(env.children)
        environment_set.add(env)
      end
    end
    environment_set
  end

  def find_environment(environment_name, environments = environment.environments.values)
    env = find_all_environments(environments).select do |environment|
      environment.name == environment_name
    end
    if env.size == 1
      return env.first
    else
      fail "Cannot find environment '#{environment_name}'"
    end
  end

  def find_virtual_service_that_i_depend_on(service, environments = [environment])
    environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.is_a?(Stacks::MachineSet) && service[0].eql?(virtual_service.name) &&
           service[1].eql?(env.name)
          return virtual_service
        end
      end
    end
    fail "Cannot find service #{service[0]} in #{service[1]}, that I depend_on"
  end
end
