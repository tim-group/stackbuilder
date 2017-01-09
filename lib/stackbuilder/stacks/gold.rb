
module Stacks::Gold
  require 'stackbuilder/stacks/namespace'
  require 'stackbuilder/stacks/gold/win_node'
  require 'stackbuilder/stacks/gold/ubuntu_node'

  def self.extended(object)
    object.configure
  end

  def configure
    on_bind do
    end

    on_bind do |_machineset, environment|
      @environment = environment
      instance_eval(&@config_block)
      bind_children(environment)
    end
  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def win(win_version, app_version, options)
    name = "#{win_version}-#{app_version}-gold"
    options[:master_image_file] = "#{win_version}-#{app_version}-master.img"
    node = Stacks::Gold::WinNode.new(self, name, environment, environment.sites.first, nil)
    node.options = options
    node.networks = [:mgmt]
    node.win_version = win_version
    @definitions[random_name] = node
  end

  def ubuntu(ubuntu_version)
    name = "ubuntu-#{ubuntu_version}-gold"
    node = Stacks::Gold::UbuntuNode.new(self, name, environment, environment.sites.first, nil)
    node.networks = [:mgmt]
    node.ubuntu_version = ubuntu_version
    @definitions[random_name] = node
  end
end
