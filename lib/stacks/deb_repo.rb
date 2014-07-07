require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::DebRepo < Stacks::MachineDef

  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::deb_repo' => {}
    }
  end

  def to_spec
    specs = super
    cname = {
      :cnames => {
        :mgmt =>  {
          'aptly-master'     => "#{qualified_hostname(:mgmt)}",
          'deb-transitional' => "#{qualified_hostname(:mgmt)}"
        }
      }
    }
    specs.merge!(cname)
    specs
  end
end

