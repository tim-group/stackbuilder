require 'stackbuilder/stacks/namespace'

class Stacks::Services::Puppetdb < Stacks::MachineDef
  # FIXME: Clean up this accessor
  attr_accessor :cnames

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    modify_storage('/' => { :size => '20G' })
    @vcpus = '16'
    @ram = '12582912' # 12GB
    @networks = [:mgmt]
  end

  def needs_signing?
    true
  end

  def needs_poll_signing?
    false
  end

  def to_enc
    enc = super()
    dependant_instances = @virtual_service.dependant_instance_fqdns(location, [:mgmt], false)
    enc.merge!('role::puppetdb'  => {
                 'allowed_hosts' => dependant_instances,
                 'version'       => @virtual_service.version
               })
    enc
  end
end
