require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::StandaloneServer < Stacks::MachineDef
  attr_reader :environment

  def initialize(base_hostname, location, &block)
    super(base_hostname)
    block.call unless block.nil?
  end

  def bind_to(environment)
    super(environment)
  end

  def to_specs
    return [{
      :hostname => @hostname,
      :domain => @domain,
      :fabric => @fabric,
      :networks => @networks,
      :qualified_hostnames => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }]
  end
end
