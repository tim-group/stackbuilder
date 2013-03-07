require 'stacks/namespace'

class Stacks::Nat
  attr_reader :from
  attr_reader :to

  def initialize(from, to)
    @from = from
    @to = to
  end
end
