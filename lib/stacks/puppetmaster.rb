require 'stacks/namespace'

class Stacks::PuppetMaster < Stacks::MachineDef

  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end

  def needs_signing?
    true
  end

  def to_spec
    return {
      :hostname            => @hostname,
      :networks            => @networks,
      :domain              => @domain,
      :fabric              => @fabric,
      :template            => 'puppetmaster',
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }],
      :cnames              => { :mgmt =>  { 'puppet' => "#{qualified_hostname(:mgmt)}" } },
      :ram                 => '2097152'
    }
  end

  def to_enc
  end
end
