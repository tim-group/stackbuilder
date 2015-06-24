require 'stackbuilder/stacks/namespace'

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
      fail "Unkown version of Windows: #{win_version}"
    end
    spec[:template] = "#{@win_version}gold"
    spec[:wait_for_shutdown] = 300
    spec
  end
end
