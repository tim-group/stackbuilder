require 'stackbuilder/stacks/namespace'

class Stacks::Services::PuppetMaster < Stacks::MachineDef
  attr_accessor :cnames

  def initialize(machineset, index)
    super(machineset.name + "-" + index, [:mgmt])

    # the puppet repo takes over 15GB as of 25.03.2015
    modify_storage('/' => { :size => '25G' })
    @vcpus = '8'
    @ram = '4194304' # 4GB
  end

  def needs_signing?
    false
  end

  def needs_poll_signing?
    false
  end

  def to_enc
    {
      # declared in 01_stacks.pp. don't use enc, as it causes a duplicate
      # declaration error. this is for bootstrapping reasons
    }
  end

  def to_spec
    specs = super
    puppetmaster_special = {
      :template            => 'puppetmaster',
      :cnames              => {
        :mgmt => {
          'puppet' => "#{qualified_hostname(:mgmt)}"
        }
      }
    }
    puppetmaster_special[:cnames] = cnames unless cnames.nil?
    specs.merge!(puppetmaster_special)
    specs
  end
end
