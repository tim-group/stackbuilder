require 'stackbuilder/stacks/core/namespace'

class Stacks::Core::Services
  attr_accessor :allocator
  attr_accessor :dns
  attr_accessor :compute_controller
  attr_accessor :logger

  def initialize(arguments)
    @allocator = arguments[:allocator]
    @compute_controller = arguments[:compute_controller]
    @dns = arguments[:dns_service] || "you must specify a dns service"
    @logger = arguments[:logger] || Logger.new(STDOUT)
  end
end
