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
    spec[:template] = "#{@win_version}gold"
    spec[:wait_for_shutdown] = 300
    spec
  end
end
