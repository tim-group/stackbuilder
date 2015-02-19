
require 'stacks/namespace'

module Stacks::Gold
  def self.extended(object)
    object.configure
  end

  def configure
    on_bind do
    end

    on_bind do |m, environment|
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

class Stacks::Gold::WinNode < Stacks::MachineDef
  attr_reader :options

  def initialize(base_hostname, win_version, options)
    super(base_hostname, [:mgmt])
    @options = options
    @win_version = win_version
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    modify_storage('/'.to_sym => {
                     :prepare => {
                       :options => {
                         :create_in_fstab => false,
                         :path   => "#{options[:master_location]}#{options[:master_image_file]}",
                         :resize => false
                       }
                     }
                   })
    case @win_version
    when 'win7'
      modify_storage('/'.to_sym => {
                       :size => '15G'
                     })
    when 'xp'
      modify_storage('/'.to_sym => {
                       :size => '8G',
                       :prepare => {
                         :options => {
                           :virtio => false
                         }
                       }
                     })
    else
      raise "Unkown version of Windows: #{win_version}"
    end
    spec[:template] = "#{@win_version}gold"
    spec[:wait_for_shutdown] = 300
    spec
  end
end

class Stacks::Gold::UbuntuNode < Stacks::MachineDef
  attr_reader :options

  def initialize(base_hostname, ubuntu_version)
    super(base_hostname, [:mgmt])
    @ubuntu_version = ubuntu_version
    @options = options
    modify_storage('/'.to_sym => {
                     :prepare => {
                       :method =>  'format',
                       :options => {
                         :resize => false,
                         :create_in_fstab => false,
                         :type => 'ext4',
                         :shrink_after_unmount => true
                       }
                     }
                   })
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "ubuntu-#{@ubuntu_version}"
    spec[:dont_start] = true
    spec[:storage]['/'.to_sym][:prepare][:options].delete(:path)
    spec
  end
end
