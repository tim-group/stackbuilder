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

      dynamic_deps = (thing.respond_to?(:establish_dependencies) ? thing.establish_dependencies : []).map do |dep|
        Stacks::Dependencies::ServiceDependency.new(thing, Stacks::Dependencies::ServiceSelector.new(dep[0], dep[1]))
      end
      dependencies.push [thing, thing.depends_on + dynamic_deps]
    end

    dependencies
  end

  def lookup(dependency, all_environments)
    cached_virtual_service = @lookup_cache[dependency]
    return cached_virtual_service unless cached_virtual_service.nil?

    virtual_service = lookup_single_dependency(all_environments, dependency)
    @lookup_cache[dependency] = virtual_service
    virtual_service
  end

  def lookup_single_dependency(all_environments, dependency)
    found_virtual_service = nil
    all_environments.each do |env|
      env.accept do |virtual_service|
        if virtual_service.is_a?(Stacks::CustomServices)
          virtual_service.k8s_machinesets.values.each do |machineset|
            found_virtual_service = machineset if dependency.to_selector.matches(dependency.from, machineset)
          end
        end
        found_virtual_service = virtual_service if dependency.to_selector.matches(dependency.from, virtual_service)
      end
    end
    found_virtual_service
  end
end
