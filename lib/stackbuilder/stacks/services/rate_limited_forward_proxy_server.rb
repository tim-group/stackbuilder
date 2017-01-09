require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::RateLimitedForwardProxyServer < Stacks::MachineDef
  attr_accessor :tc_rate

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @tc_rate = '8Mbit'
  end

  def to_enc
    enc = super()
    enc.merge!('role::rate_limited_forward_proxy' => { 'tc_rate' => @tc_rate })
    enc
  end
end
