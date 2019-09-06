module Helpers
  def eval_stacks(validate = true, &block)
    Stacks::Factory.new(Stacks::Inventory.from(validate, &block))
  end
end

RSpec.configure do |c|
  $options = {
    :verbose => 0
  }

  c.include Helpers
end
