require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/dependency'
require 'pp'

module Stacks::Dependent

  attr_reader :dependencies

  def depends_on_new(dependable_name, service_name, environment_name=@environment.name)
    @dependencies << Stacks::Dependency.new(dependable_name, service_name, environment_name)
  end

  def resolve_dependencies
    # Check that every dependable that a dependent depends on is defined
    @dependencies.each do |dep|
      dep_env = @environment.find_environment(dep.environment_name)
      service = find_service_in_environment(dep.service_name, dep_env, Stacks::MachineSet)
      service = find_service_in_environment(dep.service_name, dep_env, Stacks::MachineDef) if service.nil?
      fail("Unable to resolve dependency: Cannot find service '#{dep.service_name}' in environment '#{dep.environment_name}' for dependable '#{dep.dependable_name}' required by service '#{self.kind_of?(Stacks::MachineDef) ? mgmt_fqdn : @name}' in environment '#{@environment.name}'") if service.nil?
      dependable = service.dependable_by_name(dep.dependable_name)
      fail("Unable to resolve dependency: Cannot find dependable '#{dep.dependable_name}' on service '#{dep.service_name}' in environment '#{dep.environment_name}' required by service '#{self.kind_of?(Stacks::MachineDef) ? mgmt_fqdn : @name}' in environment '#{@environment.name}'") if dependable.empty?
    end

    # Work through all of a machines dependencies to find duplicates
    @dependencies.each do |dep|
      deps = @dependencies.select do |dep2|
        dep == dep2
      end
      fail("Duplicate dependency: #{self.kind_of?(Stacks::MachineDef) ? mgmt_fqdn : @name} has dependency '#{dep.dependable_name}' on service '#{dep.service_name}' in environment '#{dep.environment_name}' defined more than once") if deps.length != 1
    end

    # Work through a machines associated machine_set dependencies to find duplicates
    if self.kind_of? Stacks::MachineDef
      if self.respond_to? :virtual_service
        unless virtual_service.nil? or virtual_service.dependencies.empty?
          @dependencies.each do |dep|
            dupe_deps = virtual_service.dependencies.select do |dep2|
              dep == dep2
            end
            fail("Duplicate dependency: #{mgmt_fqdn} has dependency '#{dep.dependable_name}' on service '#{dep.service_name}' in environment '#{dep.environment_name}' that is also defined by machine_set #{virtual_service.name}") if dupe_deps.length > 0
          end
        end
      end

    # Work through a machine_sets associated machines dependencies to find duplicates
    elsif self.kind_of? Stacks::MachineSet
      unless @dependencies.empty? or @definitions.empty?
        @definitions.each_key do |machine_id|
          unless @definitions[machine_id].dependencies.empty?
            @dependencies.each do |dep|
              dupe_deps = @definitions[machine_id].dependencies.select do |dep2|
                dep == dep2
              end
              fail("Duplicate dependency: #{@name} has dependency '#{dep.dependable_name}' on service '#{dep.service_name}' in environment '#{dep.environment_name}' that is also defined by one of its associated machines '#{@definitions[machine_id].mgmt_fqdn}'") if dupe_deps.length > 0
            end
          end
        end
      end
    end
  end

  def init_dependencies
    @dependencies = [] if @dependencies.nil?
  end

  def dependencies_to_hash
    merged_hash = {}
    @dependencies.each do |dependency|
      merged_hash.merge! dependency.to_hash
    end
    merged_hash
  end

  private
  def self.extended(object)
    object.init_dependencies
  end

  def find_service_in_environment(service_name, environment, class_name_filter)
    service = nil
    environment.accept do |child|
      child_name = child.kind_of?(Stacks::MachineDef) ? child.mgmt_fqdn : child.name
      if child.kind_of? class_name_filter and
         child_name == service_name and
         child.environment == environment
          service = child
          break
      end
    end
    service
  end
end
