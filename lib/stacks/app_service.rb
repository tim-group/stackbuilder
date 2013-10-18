
module Stacks::AppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application

  def configure()
    @ports = [8000]
  end
end
