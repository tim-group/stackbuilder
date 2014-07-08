require 'stacks/namespace'

class Stacks::PuppetMaster < Stacks::MachineDef

  attr_accessor :cnames
  def initialize(machineset, index, &block)
    super(machineset.name + "-" + index, [:mgmt])
  end

  def needs_signing?
    false
  end

  def to_enc
    {
      'role::dev_puppetmaster' => {}
    }
  end

  def to_spec
    specs = super
    puppetmaster_special = {
      :template            => 'puppetmaster',
      :cnames              => {
        :mgmt =>  {
         'puppet' => "#{qualified_hostname(:mgmt)}"
        }
      },
    }
    puppetmaster_special[:cnames] = cnames unless cnames.nil?
    specs.merge!(puppetmaster_special)
    specs
  end

end
