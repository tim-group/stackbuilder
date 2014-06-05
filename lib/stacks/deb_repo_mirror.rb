require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::DebRepoMirror < Stacks::MachineDef

  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::deb_repo_mirror' => {}
    }
  end

  def to_specs
    cname = { :cnames => { :mgmt =>  { 'deb-transitional' => "#{qualified_hostname(:mgmt)}" } } }
    specs = super.shift
    specs.merge!(cname)
    [specs]
  end
end

