require 'stacks/namespace'

module Stacks::Selenium
end

module Stacks::Selenium::Grid
  attr_reader :hub

  def self.extended(object)
    object.configure()
  end

  def configure()
    on_bind do
      @hub = create_hub()
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
      @definitions[name] = Stacks::Selenium::XpNode.new(name, self.hub, options)
      server.ram   = @ram unless @ram.nil?
    end
  end

  def ubuntu(options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "browser-#{index}"
      @definitions[name] = Stacks::Selenium::UbuntuNode.new(name, self.hub)
      server.ram   = @ram unless @ram.nil?
    end
  end
end

class Stacks::Selenium::XpNode < Stacks::MachineDef
  attr_reader :hub
  attr_reader :options

  def initialize(base_hostname, hub, options)
    super(base_hostname, [:mgmt])
    @hub = hub
    @options = options
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "xpboot"
    spec[:se_version] = options[:se_version]
    spec[:gold_image_path] = options[:gold_image]
    spec[:se_hub] = self.hub.mgmt_fqdn
    spec[:launch_script] = "start-grid.bat"
    spec
  end

end

class Stacks::Selenium::UbuntuNode < Stacks::MachineDef
  attr_reader :hub

  def initialize(base_hostname, hub)
    super(base_hostname, [:mgmt])
    @hub = hub
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "senode"
    spec[:se_version] = "2.32.0"
    spec[:se_hub] = self.hub.mgmt_fqdn
    spec
  end
end


class Stacks::Selenium::Hub < Stacks::MachineDef
  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec
  end
end
