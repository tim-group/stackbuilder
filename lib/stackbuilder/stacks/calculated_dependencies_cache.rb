require 'stackbuilder/stacks/dependencies'

class Stacks::CalculatedDependenciesCache
  def initialize
    @cache = nil
    @environment = nil
  end

  def reset(environment)
    @cache = nil
    @environment = environment
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
end
