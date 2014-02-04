require 'stacks/core/namespace'

class Stacks::Core::Services
  attr_accessor :allocator
  attr_accessor :compute_controller
  attr_accessor :logger

  def initialize(arguments)
    @allocator = arguments[:allocator]
    @compute_controller = arguments[:compute_controller]
    @logger = arguments[:logger] || Logger.new(STDOUT)
  end
end
