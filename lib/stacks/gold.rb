
module Stacks::Gold
  require 'stacks/namespace'
  require 'stacks/gold/win_node'
  require 'stacks/gold/ubuntu_node'

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

    @definitions[name] = Stacks::Gold::WinNode.new(name, win_version, options)
  end

  def ubuntu(ubuntu_version)
    name = "ubuntu-#{ubuntu_version}-gold"
    @definitions[name] = Stacks::Gold::UbuntuNode.new(name, ubuntu_version)
  end
end
