require 'stackbuilder/stacks/namespace'

class Stacks::Gold::UbuntuNode < Stacks::MachineDef
  attr_reader :options
  attr_accessor :ubuntu_version

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @ubuntu_version = nil
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

  def to_enc
    super
    {}
  end

  def to_spec
    spec = super
    spec[:template] = "ubuntu-#{@ubuntu_version}"
    spec[:dont_start] = true
    spec[:storage]['/'.to_sym][:prepare][:options].delete(:path)
    spec
  end
end
