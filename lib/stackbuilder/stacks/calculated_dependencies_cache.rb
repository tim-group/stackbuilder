require 'stackbuilder/stacks/dependencies'

class Stacks::CalculatedDependenciesCache
  def initialize
    @cache = nil
    @environment = nil
    @lookup_cache = {}
  end

  def reset(environment)
    @cache = nil
    @environment = environment
    @lookup_cache = {}
  end

  def get
    @cache ||= calculate_dependencies
  end

  def calculate_dependencies
    dependencies = []
    @environment.virtual_services.each do |virtual_service|
      next if !virtual_service.is_a?(Stacks::MachineDefContainer)
      next if !virtual_service.respond_to?(:depends_on)

      if virtual_service.respond_to?(:establish_dependencies)
        dependencies.push [virtual_service, virtual_service.establish_dependencies]
      else
        dependencies.push [virtual_service, virtual_service.depends_on]
      end
    end

    dependencies
  end

  def lookup(dependency_id, all_environments)
    cached_virtual_service = @lookup_cache[dependency_id]
    return cached_virtual_service unless cached_virtual_service.nil?

    virtual_service = lookup_single_dependency(all_environments, dependency_id)
    @lookup_cache[dependency_id] = virtual_service
    virtual_service
  end

  def lookup_single_dependency(all_environments, dependency)
    all_environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.is_a?(Stacks::MachineSet) &&
           dependency.name.eql?(virtual_service.name) &&
           dependency.environment_name.eql?(virtual_service.environment.name)
          return virtual_service
        end
      end
    end
  end
end
