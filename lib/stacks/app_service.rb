
module Stacks::AppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application, :ehcache

  def configure()
    @ehcache = false
    @ports = [8000]
  end

  def enable_ehcache
    @ehcache = true
  end
end
