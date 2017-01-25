require 'stackbuilder/stacks/namespace'

class Stacks::Services::NatRule
  attr_reader :from, :to, :tcp, :udp

  def initialize(from, to, tcp = true, udp = false)
    @from = from
    @to = to
    @tcp = tcp
    @udp = udp
  end
end
