require 'stacks/core/namespace'

class Services
  attr_accessor :host_repo
  attr_accessor :compute_controller

  def initialize(arguments)
    @host_repo = arguments[:host_repo]
    @compute_controller = arguments[:compute_controller]
  end
end