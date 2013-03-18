require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

class Stacks::VirtualAppService < Stacks::VirtualService
  attr_accessor :application
  attr_accessor :groups

  def initialize(name, &config_block)
    @groups = ['blue']
    super(name, &config_block)
    @port = 8000
 end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary_site]
    @domain = "#{@fabric}.net.local"
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::AppServer.new(self, index, &@config_block)
      server.group = groups[i%groups.size]
    end
    super(environment)
    self.instance_eval(&@config_block) unless @config_block.nil?
  end
end
