require 'securerandom'
require 'stackbuilder/stacks/machine_def_container'
require 'stackbuilder/stacks/dependencies'
require 'stackbuilder/stacks/namespace'
require 'uri'

class Stacks::MachineSet
  attr_accessor :auto_configure_dependencies
  attr_accessor :enable_secondary_site
  attr_accessor :groups
  attr_accessor :instances
  attr_accessor :name
  attr_accessor :port_map
  attr_accessor :ports
  attr_accessor :type
  attr_accessor :server_offset
  attr_reader :allowed_hosts
  attr_reader :default_networks
  attr_reader :depends_on

  attr_accessor :database_username

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
    @depends_on = []
    @enable_secondary_site = false
    @server_offset = 0
  end

  def secondary_site?
    @enable_secondary_site
  end

  def type_of?
    :machine_set
  end

  def identity
    "#{environment.name}_#{name.to_sym}"
  end

  def instantiate_machines(environment)
    if @instances.is_a?(Integer)
      @instances.times do |i|
        server_id = i + @server_offset
        @definitions[random_name] = instantiate_machine(server_id, environment, default_networks, :primary_site)
        if @enable_secondary_site
          @definitions[random_name] = instantiate_machine(server_id, environment, default_networks, :secondary_site)
        end
      end
    elsif @instances.is_a?(Hash)
      environment.validate_instance_sites(@instances.keys)
      @instances.each do |site, count|
        site_symbol = environment.translate_site_symbol(site)
        count.times do |c|
          server_id = c + @server_offset
          @definitions[random_name] = instantiate_machine(server_id, environment, default_networks, site_symbol)
        end
      end
    else
      fail "@instances was an un-supported type: #{instances.class}, expected Integer|Hash.\n@instances: #{@instances.inspect}"
    end
  end

  def depend_on(dependant, env = environment.name, requirement = nil)
    fail('Dependant cannot be nil') if dependant.nil? || dependant.eql?('')
    fail('Environment cannot be nil') if env.nil? || env.eql?('')
    @depends_on << [dependant, env, requirement] unless @depends_on.include? [dependant, env, requirement]
  end

  def dependency_config(fabric)
    config = {}
    if @auto_configure_dependencies
      virtual_services_that_i_depend_on.each do |dependency|
        config.merge! dependency.config_params(self, fabric)
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

  def database_dependent(username)
    self.database_username = username
  end

  public

  def configure
    on_bind do |_machineset, environment|
      @environment = environment
      instance_eval(&@config_block) unless @config_block.nil?
      instantiate_machines(environment)
      bind_children(environment)
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

  def instantiate_machine(i, environment, networks = @default_networks, location = :primary_site)
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
