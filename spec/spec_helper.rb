module Helpers
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end
end

RSpec.configure do |c|
  $options = {
    :verbose => 0
  }

  c.include Helpers
end
