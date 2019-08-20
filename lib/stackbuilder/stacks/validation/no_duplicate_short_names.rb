require 'stackbuilder/stacks/validation/validation'
class Stacks::Validation::NoDuplicateShortName < Stacks::Validation::Validation
  def initialize
    @env_dupes = {}
    @service_dupes = {}
    @output = []
  end

  def validate(prepped_inventory)
    pass = true
    prepped_inventory.environments.each do |_name, environment|
      check(environment)
    end
    @env_dupes.each do |short_name, things|
      next unless things.uniq.size > 1
      @output << "Duplicate environment short_name '#{short_name}' in environments #{things.join(', ')}"
      pass = false
    end
    @service_dupes.each do |short_name, things|
      next unless things.uniq.size > 1
      @output << "Duplicate short_name '#{short_name}' in machine_sets named #{things.join(', ')}" if things.uniq.size > 1
      pass = false
    end
    @passed = pass
  end

  def failure_output
    @output
  end

  private

  def check(thing)
    if thing.respond_to?(:short_name)
      case thing
      when Stacks::Environment
        @env_dupes[thing.short_name] = [] if @env_dupes[thing.short_name].nil?
        @env_dupes[thing.short_name] << thing.name
      when Stacks::MachineSet
        @service_dupes[thing.short_name] = [] if @service_dupes[thing.short_name].nil?
        @service_dupes[thing.short_name] << "#{thing.name}"
      else
        fail "Don't know how to handle #{thing.class}"
      end
    end

    thing.children.each do |child|
      check child
    end if thing.respond_to?(:children)
  end
end
