module Stacks 
  attr_accessor :stack_templates
  def self.extended(object)
    object.stack_templates = {}
  end

  def env(name,&block)
    env =  Stacks::Environment.new(name) 
    env.stack_templates = self.stack_templates
    env.instance_eval(&block)
    return env
  end

  def stack(name, &block)
    stack_templates[name] = lambda {
      stack = Stacks::Stack.new(name)
      stack.instance_eval(&block)
      stack 
    }
  end

end
