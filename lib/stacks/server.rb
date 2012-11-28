require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Server  < Stacks::MachineDef
  attr_reader :name
  attr_reader :server_type
  attr_reader :application_name
  attr_reader :environment_name
  attr_accessor :dependencies
  def initialize(name, application_name,environment_name, type)
    @name = name
    @application_name = application_name
    @environment_name = environment_name
    @server_type = type
  end

  def to_enc
    flattened_dependencies = {}
    dependencies.map do |dependency|
      flattened_dependencies[dependency.name] = dependency.url
    end if not dependencies.nil?

    return {
      :enc=>{
        :classes=>{
        :base=>nil,
          self.server_type=>{
            :environment=>self.environment_name,
            :application=>self.application_name,
            :dependencies=>flattened_dependencies
          }
        }
      }
    }
  end
end
