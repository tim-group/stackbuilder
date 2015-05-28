require 'stackbuilder/stacks/namespace'

class Stacks::Services::Nat
  attr_reader :from
  attr_reader :to
  attr_reader :tcp
  attr_reader :udp

  def initialize(from, to, tcp = true, udp = false)
    @from = from
    @to = to
    @tcp = tcp
    @udp = udp
  end
end
