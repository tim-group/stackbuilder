
module Stacks::AppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application

  def configure()
  end
end