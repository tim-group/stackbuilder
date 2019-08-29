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
    @environment.all_things.each do |thing|
      next if !thing.is_a?(Stacks::MachineDefContainer)
      next if !thing.respond_to?(:depends_on)

      dependencies.push [thing, thing.depends_on + (thing.respond_to?(:establish_dependencies) ? thing.establish_dependencies : [])]
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
    found_virtual_service = nil
    all_environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.is_a?(Stacks::CustomServices)
          virtual_service.k8s_machinesets.values.each do |machineset|
            next unless dependency.name.eql?(machineset.name)
            next unless dependency.environment_name.eql?(machineset.environment.name)
            found_virtual_service = machineset
          end
        end
        next unless virtual_service.is_a?(Stacks::MachineSet)
        next unless dependency.name.eql?(virtual_service.name)
        next unless dependency.environment_name.eql?(virtual_service.environment.name)
        found_virtual_service = virtual_service
      end
    end
    found_virtual_service
  end
end
