require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname

  def initialize(hostname)
    @hostname = hostname
  end

  def fqdn
    return "#{hostname}.#{environment.domain}"
  end

  def to_spec
    return {}
  end
end
