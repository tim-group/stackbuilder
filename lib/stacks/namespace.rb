module Stacks
  attr_accessor :stack_templates
  attr_accessor :environments

  def self.extended(object)
    object.stack_templates = {}
    object.environments = {}
  end

  def env(name,&block)
    env =  Stacks::Environment.new(name)
    env.instance_eval(&block)
    environments[name] = env
    return env
  end

  def generate_machines
    environments.each do |env_name,env|
      env.generate()
    end
  end

end
