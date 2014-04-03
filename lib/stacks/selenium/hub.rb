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

  def hub(options={}, name="hub-001")
    @hub = @definitions[name] = Stacks::Selenium::Hub.new(name, @definitions, options)
  end

  def winxp(version, options)
    options[:ie_version] = options[:ie_version] || version # TODO: Remove this once refstack has been updated to pass in :ie_version
    win "xp", options
  end

  def win7(version, options)
    options[:ie_version] = options[:ie_version] || version # TODO: Remove this once refstack has been updated to pass in :ie_version
    win "win7", options
  end

  def win(win_version, options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "ie#{options[:ie_version]}-#{index}"

      if win_version == "xp"
        @definitions[name] = Stacks::Selenium::XpNode.new(name, @hub, options)
      elsif win_version == "win7"
        @definitions[name] = Stacks::Selenium::Win7Node.new(name, @hub, options)
      else
        raise "Unkown version of Windows: #{win_version}"
      end
    end
  end

  def ubuntu(options)
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      name = "browser-#{index}"
      @definitions[name] = Stacks::Selenium::UbuntuNode.new(name, @hub, options)
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
    spec[:gold_image_url] = options[:gold_image]
    spec[:image_size] = "8G"

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end
    spec[:selenium_version] = options[:selenium_version] || "2.32.0" # TODO: Remove default once refstack has been updated to pass in :ie_version
    spec[:ie_version] = options[:ie_version]

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
    spec[:gold_image_url] = options[:gold_image]
    spec[:image_size] = "15G"

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end
    spec[:selenium_version] = options[:selenium_version] || "2.32.0" # TODO: Remove default once refstack has been updated to pass in :ie_version
    spec[:ie_version] = options[:ie_version]

    spec
  end

end


class Stacks::Selenium::UbuntuNode < Stacks::MachineDef
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
    spec[:template] = "senode"

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end
    spec[:selenium_version] = options[:selenium_version] || "2.32.0"

    spec
  end
end


class Stacks::Selenium::Hub < Stacks::MachineDef
  attr_reader :options

  def initialize(base_hostname, nodes, options)
    super(base_hostname, [:mgmt])
    @nodes = nodes
    @options = options
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec[:nodes] = @nodes.map {|name,node| node.name}.reject{|name,node| name==self.name}.sort
    spec[:selenium_version] = options[:selenium_version] || "2.32.0"
    spec
  end
end
