require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::DebRepoMirror < Stacks::MachineDef
  attr_accessor :cnames
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::deb_repo_mirror' => {}
    }
  end

  def to_spec
    specs = super
    cname = { :cnames => { :mgmt =>  { 'deb-transitional' => "#{qualified_hostname(:mgmt)}" } } }
    specs.merge!(cname)
    specs[:cnames] = cnames unless cnames.nil?
    specs
  end
end
