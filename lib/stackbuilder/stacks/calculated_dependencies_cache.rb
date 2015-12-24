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
end
