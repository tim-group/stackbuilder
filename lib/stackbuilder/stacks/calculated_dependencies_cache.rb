class Stacks::CalculatedDependenciesCache

  def initialize
    @cache = nil
    @environments = nil
  end

  def reset(environment)
    @cache = nil
    @environments = environment
  end

  def get
    @cache ||= calculate_dependencies_across_environments
  end

  private

  def calculate_dependencies_across_environments
    dependencies = []
    @environments.virtual_services(@environments.find_all_environments).each do |virtual_service|
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