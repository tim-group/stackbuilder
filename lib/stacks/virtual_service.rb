require 'stacks/namespace'

class Stacks::VirtualService
  attr_accessor :domain
  attr_reader :env
  attr_reader :name

  def initialize(name, env)
    @name = name
    @env = env
  end

  def url()
    return "#{env}-#{name}-vip.#{domain}"
  end
end
