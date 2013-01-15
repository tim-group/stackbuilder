module Stacks

  require 'stacks/stack'
  require 'stacks/environment'

  module DSL
    attr_accessor :stacks
    attr_accessor :environments

    def self.extended(object)
      object.stacks = {}
      object.environments = {}
    end

    def stack(name,&block)
      stack =  Stacks::Stack.new(name)
      stack.instance_eval(&block)
      stacks[name] = stack
      return stack
    end

    def env(name, options)
      environments[name] = Stacks::Environment.new(name, options)
    end

    def bind_to(environment_name)
      environment = environments[environment_name]
      raise "no environment called #{environment_name}" if environment.nil?
      stacks.values.each do |stack|
        stack.bind_to(environment)
      end
    end

    def accept(&block)
      stacks.values.each do |stack|
        stack.accept(&block)
      end
    end

  end
end
