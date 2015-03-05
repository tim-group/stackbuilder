module Stacks
  require 'stacks/stack'
  require 'stacks/environment'
  require 'stacks/standalone_server'
  require 'resolv'

  module DSL
    attr_accessor :stack_procs
    attr_accessor :environments

    def self.extended(object)
      object.stack_procs = {}
      object.environments = {}
    end

    def stack(name, &block)
      @stack_procs[name] = Proc.new do |environment|
        stack = Stacks::Stack.new(name)
        stack.instance_eval(&block)
        stack.bind_to(environment)
        stack
      end
    end

    def env(name, options, &block)
      environments[name] = Stacks::Environment.new(name, options, environments, stack_procs)
      environments[name].instance_eval(&block) unless block.nil?
    end

    def find_by_hostname(hostname)
      node = nil
      accept do |machine_def|
        if machine_def.respond_to?(:hostname) && machine_def.hostname == hostname
          node = machine_def
        end
      end
      node
    end

    def find(fqdn)
      node = nil
      accept do |machine_def|
        if machine_def.respond_to?(:mgmt_fqdn) && machine_def.mgmt_fqdn == fqdn
          node = machine_def
        end
      end
      node
    end

    def accept(&block)
      environments.values.each do |env|
        env.accept(&block)
      end
    end

    def find_environment(environment_name)
      return_environment = nil
      env_names = Set.new
      accept do |node|
        if node.kind_of?(Stacks::Environment) && node.name == environment_name
          raise "Duplicate environment detected: #{node.name}\nPlease check the stacks config to ensure you dont have two environments called '#{node.name}'." if env_names.include?("#{node.name}")
          env_names  << "#{node.name}"
          return_environment = node
        end
      end

      return_environment
    end
  end
end
