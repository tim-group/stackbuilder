require 'stackbuilder/stacks/namespace'

class Stacks::Services::Puppetserver < Stacks::MachineDef
  attr_accessor :cnames

  def initialize(machineset, index, location)
    super(machineset.name + "-" + index, [:mgmt], location)

    @puppetserver_cluster = machineset
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
    enc = super()
    puppetdb_mgmt_fqdn = @puppetserver_cluster.puppetdb_that_i_depend_on
    enc.merge!('role::puppetserver' => {
                 'storedconfigs' => true
               })
    enc['role::puppetserver']['puppetdb_server'] = puppetdb_mgmt_fqdn unless puppetdb_mgmt_fqdn.nil?
    enc
  end

  def to_spec
    specs = super
    puppetmaster_special = {
      :template            => 'puppetserver',
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
