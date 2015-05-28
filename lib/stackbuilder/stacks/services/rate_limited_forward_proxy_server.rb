require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::RateLimitedForwardProxyServer < Stacks::MachineDef
  def initialize(server_group, index)
    super(server_group.name + "-" + index, [:mgmt, :prod])
    self
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    {
      'role::rate_limited_forward_proxy' => {}
    }
  end
end
