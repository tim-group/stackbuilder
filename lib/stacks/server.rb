require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server  < Stacks::MachineDef
  attr_reader :server_type
  attr_reader :application_name
  attr_accessor :dependencies

  def initialize(name, application_name,environment, type)
    super(name, environment)
    @application_name = application_name
    @server_type = type
  end

  def to_spec
    spec = super

    flattened_dependencies = {}
    dependencies.map do |dependency|
      flattened_dependencies[dependency.name] = dependency.url
    end if not dependencies.nil?

    spec[:enc] = {
      :classes=>{
        "base"=>nil,
          self.server_type.to_s=>{
            "environment"=>self.environment.name,
            "application"=>self.application_name,
            "dependencies"=>flattened_dependencies
          }
      }
    }
    return spec
  end
end
