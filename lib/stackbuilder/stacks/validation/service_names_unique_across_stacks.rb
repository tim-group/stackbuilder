require 'stackbuilder/stacks/validation/validation'
require 'set'

class Stacks::Validation::ServiceNamesUniqueAcrossStacks < Stacks::Validation::Validation
  def initialize
    @output = []
  end

  def validate(prepped_inventory)
    pass = true

    stacks_by_service = {}

    prepped_inventory.environments.each do |_name, environment|
      environment.definitions.each do |stack_name, stack_defn|
        virtual_services = stack_defn.definitions
        virtual_services = virtual_services.merge(stack_defn.k8s_machinesets) if stack_defn.respond_to?(:k8s_machinesets)
        virtual_services.each do |vs_name, _vs_defn|
          if stacks_by_service.key?(vs_name)
            stacks_by_service[vs_name].add(stack_name)
          else
            stacks_by_service[vs_name] = Set[stack_name]
          end
        end
      end
    end

    stacks_by_service.each do |service, stacks|
      if stacks.size > 1
        @output << "Duplicate service '#{service}' in stacks #{stacks.to_a.map { |s| "'#{s}'" }.join(', ')}"
        pass = false
      end
    end
    @passed = pass
  end

  def failure_output
    @output
  end
end
