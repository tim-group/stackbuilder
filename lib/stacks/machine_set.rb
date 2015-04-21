require 'securerandom'
require 'stacks/machine_def_container'
require 'stacks/dependencies'
require 'stacks/namespace'
require 'uri'

class Stacks::MachineSet
  attr_accessor :auto_configure_dependencies
  attr_accessor :enable_secondary_site
  attr_accessor :fabric
  attr_accessor :groups
  attr_accessor :instances
  attr_accessor :name
  attr_accessor :port_map
  attr_accessor :ports
  attr_accessor :type
  attr_reader :allowed_hosts
  attr_reader :default_networks
  attr_reader :default_site
  attr_reader :depends_on

  include Stacks::MachineDefContainer

  def initialize(name, &config_block)
    @auto_configure_dependencies = true
    @bind_steps = []
    @config_block = config_block
    @definitions = {}
    @groups = ['blue']
    @instances = 2
    @name = name

    @allowed_hosts = []
    @default_networks = [:mgmt, :prod]
    @default_site = :primary_site
    @depends_on = []
    @enable_secondary_site = false
  end

  def instantiate_machines(environment)
    @instances.times do |i|
      @definitions[random_name] = instantiate_machine(i, environment, default_networks, default_site)
      if @enable_secondary_site
        @definitions[random_name] = instantiate_machine(i, environment, default_networks, :secondary_site)
      end
    end
  end

  def depend_on(dependant, env = environment.name)
    fail('Dependant cannot be nil') if dependant.nil? || dependant.eql?('')
    @depends_on << [dependant, env] unless @depends_on.include? [dependant, env]
  end

  def dependency_config
    config = {}
    if @auto_configure_dependencies
      virtual_services_that_i_depend_on.each do |dependency|
        config.merge! dependency.config_params(self)
      end
    end
    config
  end

  def allow_host(source_host_or_network)
    @allowed_hosts << source_host_or_network
    @allowed_hosts.uniq!
  end

  def on_bind(&block)
    @bind_steps << block
  end

  def bind_to(environment)
    @bind_steps.each do |step|
      step.call(self, environment)
    end
  end

  def each_machine(&block)
    on_bind do
      accept do |machine|
        block.call(machine) if machine.is_a? Stacks::MachineDef
      end
    end
  end

  public

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

  # FIXME: This should generate a unique name
  def random_name
    SecureRandom.hex(20)
  end

  private

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
