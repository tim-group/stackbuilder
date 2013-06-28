require 'stacks/namespace'

module Stacks::Selenium
end

module Stacks::Selenium::Grid
  def self.extended(object)
    object.configure()
  end

  def configure()

    on_bind do
      create_hub()
    end

    on_bind do |m,environment|
      self.instance_eval(&@config_block)
      bind_children(environment)
    end

  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end


  def create_hub(name="hub-001")
    @definitions[name] = Stacks::Selenium::Hub.new(name)
  end

  def winxp(version,options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "xp#{version}-#{index}"
      @definitions[name] = Stacks::Selenium::XpNode.new(name)
      server.ram   = @ram unless @ram.nil?
    end
  end

  def ubuntu(options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "browser-#{index}"
      @definitions[name] = Stacks::Selenium::UbuntuNode.new(name)
      server.ram   = @ram unless @ram.nil?
    end
  end
end

class Stacks::Selenium::XpNode < Stacks::MachineDef
  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end
end

class Stacks::Selenium::UbuntuNode < Stacks::MachineDef
  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end
end


class Stacks::Selenium::Hub < Stacks::MachineDef
  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end
end
