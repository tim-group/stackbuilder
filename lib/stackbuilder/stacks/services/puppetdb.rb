require 'stackbuilder/stacks/namespace'

class Stacks::Services::Puppetdb < Stacks::MachineDef
  # FIXME: Clean up this accessor
  attr_accessor :cnames

  def initialize(machineset, index, location)
    super(machineset.name + "-" + index, [:mgmt], location)

    @puppetdb_cluster = machineset
    modify_storage('/' => { :size => '20G' })
    @vcpus = '8'
    @ram = '6291456' # 6GB
  end

  def needs_signing?
    true
  end

  def needs_poll_signing?
    false
  end

  def to_enc
    enc = super()
    dependant_instances = @puppetdb_cluster.dependant_instance_fqdns(location, [:mgmt], false)
    enc.merge!('role::puppetdb'  => {
                 'allowed_hosts' => dependant_instances,
                 'version'       => @puppetdb_cluster.version
               })
    enc
  end
end
