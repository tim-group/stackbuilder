require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'
require 'securerandom'

module Stacks::MachineGroup
  def self.extended(object)
    object.configure
  end

  def configure
    on_bind do |_machineset, environment|
      @environment = environment
      configure_domain_name(environment)
      instance_eval(&@config_block) unless @config_block.nil?
      instantiate_machines(environment)
      bind_children(environment)
    end
  end

  def configure_domain_name(environment)
    @fabric = environment.options[:primary_site]
    suffix = 'net.local'
    @domain = "#{@fabric}.#{suffix}"
    case @fabric
    when 'local'
      @domain = "dev.#{suffix}"
    end
  end

  def bind_children(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def availability_group(environment)
    environment.name + "-" + name
  end

  def instantiate_machines(environment)
    @instances.times do |i|
      @definitions[random_name] = instantiate_machine(i, environment)
    end
  end

  def random_name
    SecureRandom.hex(20)
  end

  def instantiate_machine(i, environment, networks = @default_networks, location = @default_site)
    index = sprintf("%03d", i + 1)
    server = nil
    # FIXME: Temporary fix - Remove me when all stacks have a 4 param or use the default constructor.
    # Not all stacks classes have a constructor that will take all 4 variables.
    # Maintain backwards compatibility by checking the arity of the constructor.
    # If the method expects a fixed number of arguments, this number is its arity.
    # If the method expects a variable number of arguments, its arity is the additive inverse of its parameter count
    # An arity >= 0 indicates a fixed number of parameters
    # An arity < 0 indicates a variable number of parameters.
    # Digested from source: http://readruby.io/methods
    if @type.instance_method(:initialize).arity == -3
      server = @type.new(self, index, networks, location)
    else
      server = @type.new(self, index)
    end
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    if server.respond_to?(:availability_group)
      server.availability_group = availability_group(environment)
    end
    server
  end
end
