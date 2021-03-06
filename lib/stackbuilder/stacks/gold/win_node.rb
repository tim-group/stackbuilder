require 'stackbuilder/stacks/namespace'

class Stacks::Gold::WinNode < Stacks::MachineDef
  attr_reader :options
  attr_accessor :options
  attr_accessor :win_version

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @options = {}
    @win_version = nil
  end

  def to_enc
    super
    {}
  end

  def to_spec
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
    when 'win10'
      modify_storage('/'.to_sym => {
                       :size => '15G'
                     })
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
      fail "Unkown version of Windows: #{win_version}"
    end

    spec = super
    spec[:template] = "#{@win_version}gold"
    spec[:kvm_template] = 'kvm_nx_required' if @win_version == 'win10'
    spec[:wait_for_shutdown] = 600
    spec
  end
end
