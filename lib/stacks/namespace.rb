module Stacks

  require 'stacks/stack'
  require 'stacks/environment'
  require 'stacks/standalone_server'

  module DSL
    attr_accessor :stacks
    attr_accessor :stack_procs
    attr_accessor :environments

    def self.extended(object)
      object.stacks = {}
      object.stack_procs = {}
      object.environments = {}
    end

    def stack(name,&block)
      @stack_procs[name] = Proc.new do |environment|
        stack =  Stacks::Stack.new(name)
        stack.instance_eval(&block)
        stack.bind_to(environment)
        stack
      end
    end

    def env(name, options)
      environments[name] = Stacks::Environment.new(name, options)
    end

    def bind()
      environments.each do |name,env|
        bind_to(name)
      end
    end

    def bind_to(environment_name)
      environment = environments[environment_name]
      raise "no environment called #{environment_name}" if environment.nil?
      stack_procs.each do |name, stack_proc|
        stacks[environment_name + "-" + name] = stack_proc.call(environment)
      end
    end

    def enc_for(fqdn)
      node = nil
      accept do |machine_def|
        if machine_def.respond_to? :mgmt_fqdn and machine_def.mgmt_fqdn == fqdn
          node = machine_def
        end
      end

      raise "unable to locate machine called #{fqdn}" if node.nil?

      {
        'role::http_app' => {
           'application' => node.virtual_group,
           'groups' => node.groups,
           'vip' => node.vip_fqdn,
           'environment' => node.environment.name
        }
      }
    end

    def accept(&block)
      stacks.values.each do |stack|
        stack.accept(&block)
      end
    end

  end
end
