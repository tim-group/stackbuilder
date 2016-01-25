require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::RateLimitedForwardProxyServer < Stacks::MachineDef
  attr_accessor :tc_rate

  def initialize(server_group, index)
    super(server_group.name + "-" + index, [:mgmt, :prod])
    @tc_rate = '8Mbit'
    self
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    enc = super()
    enc.merge!('role::rate_limited_forward_proxy' => { 'tc_rate' => @tc_rate })
    enc
  end
end
