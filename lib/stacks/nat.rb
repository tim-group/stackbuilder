require 'stacks/namespace'

class Stacks::Nat
  attr_reader :from
  attr_reader :to
  attr_reader :proto

  def initialize(from, to, proto)
    @from = from
    @to = to
    @proto = proto
  end
end
