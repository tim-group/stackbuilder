require 'stacks/namespace'

module Stacks::Selenium
end

module Stacks::Selenium::Grid

  def self.extended(object)
    object.configure()
  end

  def configure()
    on_bind do
    end

    on_bind do |m,environment|
      @environment = environment
      self.instance_eval(&@config_block)
      bind_children(environment)
    end

  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def hub(name="hub-001")
    @hub = @definitions[name] = Stacks::Selenium::Hub.new(name, @definitions)
  end

  def winxp(version,options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "xp#{version}-#{index}"
      @definitions[name] = Stacks::Selenium::XpNode.new(name, @hub, options)
    end
  end

  def win7(version,options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "win7ie#{version}-#{index}"
      @definitions[name] = Stacks::Selenium::Win7Node.new(name, @hub, options)
    end
  end

  def ubuntu(options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "browser-#{index}"
      @definitions[name] = Stacks::Selenium::UbuntuNode.new(name, @hub)
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
    spec[:kvm_template] = 'kvm_no_virtio'
    spec[:se_version] = options[:se_version]
    spec[:gold_image_url] = options[:gold_image]
    spec[:image_size] = "8G"

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end

    spec[:launch_script] = "start-grid.bat"
    spec
  end

end

class Stacks::Selenium::Win7Node < Stacks::MachineDef
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
    spec[:template] = "win7boot"

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end

    spec[:gold_image_url] = options[:gold_image]
    spec[:image_size] = "15G"
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

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end

    spec
  end
end


class Stacks::Selenium::Hub < Stacks::MachineDef
  def initialize(base_hostname, nodes)
    super(base_hostname, [:mgmt])
    @nodes = nodes
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec[:nodes] = @nodes.map {|name,node| node.name}.reject{|name,node| name==self.name}.sort
    spec
  end
end
