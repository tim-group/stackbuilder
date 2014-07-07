require 'stacks/namespace'

class Stacks::PuppetMaster < Stacks::MachineDef

  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end

  def needs_signing?
    false
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
    specs.merge!(puppetmaster_special)
    specs
  end

  def to_enc
  end
end
