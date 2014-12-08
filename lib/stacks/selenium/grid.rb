require 'stacks/selenium/namespace'

require 'stacks/selenium/hub'
require 'stacks/selenium/ubuntu_node'
require 'stacks/selenium/xp_node'
require 'stacks/selenium/win7_node'

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