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
  attr_accessor :role_in_name
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
    @add_role_to_name = []
    @role_in_name = false
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

  def instances_usage_with_role
    "Below is an example of correct usage:\n \
 @instances = {\n \
   'oy' => {\n \
     :master => 1,\n \
     :slave  => 2\n \
   },\n \
   'st' => {\n \
     :master => 1,\n \
     :slave  => 0\n \
   }\n \
 }\n\
 This is what you specified:\n @instances = #{@instances.inspect}\n"
  end

  def instances_usage
    "Below is an example of correct usage:\n \
 @instances = {\n\
   'oy' => 1,\n\
   'st' => 1\n\
 }\n\
 This is what you specified:\n @instances = #{@instances.inspect}\n"
  end

  def validate_instances(environment)
    if @instances.is_a?(Integer)
      fail "You cannot specify self.role_in_name = true without defining roles in @instances\n \
      #{instances_usage_with_role}" if @role_in_name
    elsif @instances.is_a?(Hash)
      environment.validate_instance_sites(@instances.keys)
      @instances.each do |_site, count|
        if count.is_a?(String)
          fail "You must specify Integers when using @instances in a hash format\n #{instances_usage}"
        elsif count.is_a?(Integer)
          fail "You cannot specify self.role_in_name = true without defining roles in @instances\n \
          #{instances_usage_with_role}" if @role_in_name
        elsif count.is_a?(Hash)
          count.each do |role, num|
            fail "You must specify Integers when using @instances in a hash format\n #{instances_usage_with_role}" if num.is_a?(String)
            fail "Role: #{role} must be a symbol\n #{instances_usage_with_role}" unless role.is_a?(Symbol)
          end
        else
          fail "@instances hash contains invalid item #{count} which is a #{count.class} expected Integer / Symbol"
        end
      end
    else
      fail "You must specify Integer or Hash for @instances. You provided a #{instances.class}"
    end
  end

  def instantiate_machines(environment)
    validate_instances(environment)
    if @instances.is_a?(Integer)
      1.upto(@instances) do |i|
        server_index = i + @server_offset
        instantiate_machine(server_index, environment, environment.sites.first)
        if @enable_secondary_site
          instantiate_machine(server_index, environment, environment.sites.last)
        end
      end
    elsif @instances.is_a?(Hash)
      @instances.each do |site, count|
        if count.is_a?(Integer)
          1.upto(count) do |c|
            server_index = @server_offset + c
            instantiate_machine(server_index, environment, site)
          end
        elsif count.is_a?(Hash)
          count.each do |role, num|
            1.upto(num) do |c|
              server_index = @server_offset + c
              instantiate_machine(server_index, environment, site, role)
            end
          end
        else
          fail "Instances hash contains invalid item #{count} which is a #{count.class} expected Integer / Symbol"
        end
      end
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

  def instantiate_machine(index, environment, site, role = nil, custom_name = '')
    vm_name = "#{name}#{custom_name}-" + sprintf("%03d", index)
    vm_name = "#{name}-#{role}-" + sprintf("%03d", index) if @role_in_name
    vm_name = "#{name}" if @type == Stacks::Services::ExternalServer
    server = @type.new(self, vm_name, environment, site, role)
    server.group = groups[(index - 1) % groups.size] if server.respond_to?(:group)
    if server.respond_to?(:availability_group)
      server.availability_group = availability_group(environment)
    end
    server.index = index
    @definitions[random_name] = server
    server
  end
end
