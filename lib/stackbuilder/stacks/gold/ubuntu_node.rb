require 'stackbuilder/stacks/namespace'

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
                         :shrink_after_unmount => true,
                       },
                     },
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
