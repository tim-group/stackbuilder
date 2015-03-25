require 'stacks/namespace'

class Stacks::PuppetMaster < Stacks::MachineDef
  attr_accessor :cnames
  attr_accessor :puppetmaster_role

  def initialize(machineset, index)
    super(machineset.name + "-" + index, [:mgmt])

    @puppetmaster_role = 'dev'
  end

  def needs_signing?
    false
  end

  def to_enc
    puppet_role = case @puppetmaster_role
                  when 'dev'  then 'role::dev_puppetmaster'
                  when 'prod' then 'role::prod_puppetmaster'
                  else raise "unknown puppetmaster_role #{puppetmaster_role} for stack PuppetMaster"
    end
    {
      puppet_role => {}
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
      }
    }
    puppetmaster_special[:cnames] = cnames unless cnames.nil?
    specs.merge!(puppetmaster_special)
    specs
  end
end
