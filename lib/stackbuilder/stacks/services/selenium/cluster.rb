require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/services/selenium/namespace'

module Stacks::Services::Selenium::Cluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :hub, :selenium_version, :firefox_version, :nodespecs

  def configure
    @hub = nil
    @selenium_version = '2.32.0'
    @firefox_version = nil
    @nodespecs = []
  end

  def instantiate_node(nodespec)
    nodespec[:instances].times do |i|
      index = sprintf("%03d", i + 1)
      node = nil
      case nodespec[:type]
      when "ubuntu"
        node_name = "#{name}-browser-#{index}"
        node = Stacks::Services::Selenium::UbuntuNode.new(node_name, @hub,
                                                          :selenium_version => @selenium_version,
                                                          :firefox_version => @firefox_version)
      when "winxp"
        node_name = "#{name}-ie#{nodespec[:ie_version]}-#{index}"
        node = Stacks::Services::Selenium::XpNode.new(node_name, @hub,
                                                      :selenium_version => @selenium_version,
                                                      :gold_image => nodespec[:gold_image],
                                                      :ie_version => nodespec[:ie_version])
      when "win7"
        node_name = "#{name}-ie#{nodespec[:ie_version]}-#{index}"
        node = Stacks::Services::Selenium::Win7Node.new(node_name, @hub,
                                                        :selenium_version => @selenium_version,
                                                        :gold_image => nodespec[:gold_image],
                                                         :ie_version => nodespec[:ie_version])
      else
        fail "unknown Selenium node type"
      end
      @definitions[node_name] = node

    end
  end

  def instantiate_machines(_environment)
    @nodespecs.each do |nodespec|
      instantiate_node nodespec
    end
  end
end
