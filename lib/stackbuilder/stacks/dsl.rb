require 'stackbuilder/stacks/namespace'

module Stacks
  module DSL
    attr_accessor :stack_procs
    attr_accessor :environments
    attr_accessor :calculated_dependencies_cache

    def self.extended(object)
      object.stack_procs = {}
      object.environments = {}
      object.calculated_dependencies_cache = Stacks::CalculatedDependenciesCache.new
    end

    def stack(name, &block)
      @stack_procs[name] = Proc.new do |environment|
        stack = Stacks::CustomServices.new(name)
        stack.instance_eval(&block)
        stack.bind_to(environment)
        stack
      end
    end

    def env(name, options, &block)
      environments[name] = Stacks::Environment.new(name, options, nil, environments, stack_procs, @calculated_dependencies_cache)
      environments[name].instance_eval(&block) unless block.nil?
      calculated_dependencies_cache.reset(environments[name])
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

    def fqdn_list
      hosts = []
      accept do |machine_def|
        hosts << machine_def.mgmt_fqdn if machine_def.respond_to?(:mgmt_fqdn)
      end
      hosts
    end

    def all_hosts
      hosts = []
      accept do |machine_def|
        hosts << machine_def if machine_def.respond_to?(:to_enc)
      end
      hosts
    end

    def exist?(fqdn)
      found = false
      accept do |machine_def|
        if machine_def.respond_to?(:mgmt_fqdn) && machine_def.mgmt_fqdn == fqdn
          found = true
        end
      end
      found
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
        if node.is_a?(Stacks::Environment) && node.name == environment_name
          if env_names.include?("#{node.name}")
            fail "Duplicate environment detected: #{node.name}\n" \
              "Please check the stacks config to ensure you dont have two environments called '#{node.name}'."
          end
          env_names << "#{node.name}"
          return_environment = node
        end
      end

      return_environment
    end
  end
end
