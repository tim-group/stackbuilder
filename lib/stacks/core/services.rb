require 'stacks/core/namespace'

class Stacks::Core::Services
  attr_accessor :host_repo
  attr_accessor :compute_controller
  attr_accessor :logger

  def initialize(arguments)
    @host_repo = arguments[:host_repo]
    @compute_controller = arguments[:compute_controller]
    @logger = arguments[:logger] || Logger.new(STDOUT)
  end
end