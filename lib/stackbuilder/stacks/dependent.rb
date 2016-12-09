require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/dependency'
require 'pp'

module Stacks::Dependent

  attr_reader :dependencies

  def depends_on_new(dependable_name, service_name, environment_name=@environment.name)
    @dependencies << Stacks::Dependency.new(dependable_name, service_name, environment_name)
  end

  def resolve_dependencies
    @dependencies.each do |dep|
      env = @environment.find_environment(dep.environment_name)
      service = find_service_in_environment(dep.service_name, env)
    end
  end

  def init_dependencies
    @dependencies = [] if @dependencies.nil?
  end

  private
  def self.extended(object)
    object.init_dependencies
  end

  def find_service_in_environment(service_name, environment)
    services = []
    environment.accept do |child|
      if child.kind_of? Stacks::MachineDefContainer
        services << child if child.name == service_name
      end
    end

    fail("Unable to find service #{service_name} in environment #{environment.name}") unless services.length == 1

    services.first
  end
end
