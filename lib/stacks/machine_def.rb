require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname, :domain

  def initialize(hostname)
    @hostname = hostname
    @networks = [:mgmt, :prod]
  end

  def name
    return @hostname
  end

  def children
    return []
  end

  def accept(&block)
    block.call(self)
  end

  def bind_to(environment)
  end

  def to_specs
    return []
  end

  def qualified_hostname(network)
    raise "no such network '#{network}'" unless @networks.include?(network)
    if network == 'prod'
      return "#{@hostname}.#{@domain}"
    else
      return "#{@hostname}.#{network}.#{@domain}"
    end
  end

  def mgmt_fqdn
    return qualified_hostname(:mgmt)
  end
end
