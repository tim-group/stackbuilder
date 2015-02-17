require 'stacks/selenium/namespace'

require 'stacks/selenium/hub'
require 'stacks/selenium/ubuntu_node'
require 'stacks/selenium/xp_node'
require 'stacks/selenium/win7_node'

module Stacks::Selenium::Cluster
  def self.extended(object)
    object.configure()
  end

  attr_accessor :hub, :selenium_version, :nodespecs

  def configure()
    @hub = nil
    @selenium_version = '2.32.0'
    @nodespecs = []
  end

  def instantiate_node(nodespec)
    nodespec[:instances].times do |i|
      index = sprintf("%03d", i + 1)
      case nodespec[:type]
      when "ubuntu"
        node_name = "#{name}-browser-#{index}"
        @definitions[node_name] = Stacks::Selenium::UbuntuNode.new(node_name, @hub, { :selenium_version => @selenium_version })
      when "winxp"
        node_name = "#{name}-ie#{nodespec[:ie_version]}-#{index}"
        @definitions[node_name] = Stacks::Selenium::XpNode.new(node_name, @hub, { :selenium_version => @selenium_version,
                                                                                  :gold_image => nodespec[:gold_image],
                                                                                  :ie_version => nodespec[:ie_version] })
      when "win7"
        node_name = "#{name}-ie#{nodespec[:ie_version]}-#{index}"
        @definitions[node_name] = Stacks::Selenium::Win7Node.new(node_name, @hub, { :selenium_version => @selenium_version,
                                                                                    :gold_image => nodespec[:gold_image],
                                                                                    :ie_version => nodespec[:ie_version] })
      else
        raise "unknown Selenium node type"
      end
    end
  end

  def instantiate_machines(environment)
    @nodespecs.each do |nodespec|
      instantiate_node nodespec
    end
  end

end
