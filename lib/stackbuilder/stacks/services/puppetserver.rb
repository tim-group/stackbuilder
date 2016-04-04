require 'stackbuilder/stacks/namespace'

class Stacks::Services::Puppetserver < Stacks::MachineDef
  attr_accessor :cnames

  def initialize(machineset, index, location)
    super(machineset.name + "-" + index, [:mgmt], location)

    @puppetserver_cluster = machineset
    # the puppet repo takes over 15GB as of 25.03.2015
    modify_storage('/' => { :size => '25G' })
    modify_storage('/var/lib/puppet/ssl' => {
                     :type       => 'data',
                     :size       => '1G',
                     :persistent => true
                   })
    @vcpus = '9'
    @ram = '8777216'
  end

  def needs_signing?
    false
  end

  def needs_poll_signing?
    false
  end

  def dont_persist_certs
    modify_storage('/var/lib/puppet/ssl' => {
                     :persistent => false
                   })
  end

  def to_enc
    enc = super()
    puppetdb_mgmt_fqdn = @puppetserver_cluster.puppetdb_that_i_depend_on
    stored_configs = puppetdb_mgmt_fqdn.nil? ? false : true
    enc.merge!('role::puppetserver' => {
                 'storedconfigs' => stored_configs
               })
    enc['role::puppetserver']['puppetdb_server'] = puppetdb_mgmt_fqdn unless puppetdb_mgmt_fqdn.nil?
    enc
  end

  def to_spec
    specs = super
    puppetserver_special = {
      :template            => 'puppetserver',
      :cnames              => {}
    }
    specs.merge!(puppetserver_special)
    specs
  end
end
