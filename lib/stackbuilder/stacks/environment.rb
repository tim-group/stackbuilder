require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def_container'

class Stacks::Environment
  attr_reader :domain_suffix
  attr_reader :environments
  attr_reader :parent
  attr_reader :name
  attr_reader :options
  attr_reader :primary_site
  attr_reader :secondary_site

  include Stacks::MachineDefContainer

  def initialize(name, options, parent, environments, stack_procs)
    @name = name
    @options = options
    @environments = environments
    @stack_procs = stack_procs
    @definitions = {}
    @persistent_storage_supported =
      options[:persistent_storage_supported].nil? ? true : options[:persistent_storage_supported]
    @every_machine_destroyable =
      options[:every_machine_destroyable].nil? ? false : options[:every_machine_destroyable]
    @primary_site = options[:primary_site]
    @secondary_site = options[:secondary_site]
    @domain_suffix = options[:domain_suffix] || 'net.local'
    @parent = parent
    @children = []
  end

  def child?(environment)
    children.include?(environment)
  end

  def child_or_self?(environment)
    children.include?(environment) || environment == self
  end

  def sub_environments
    children.select { |node| node.is_a?(Stacks::Environment) }
  end

  def sub_environment_names
    names = []
    sub_environments.each do |sub_environment|
      names << sub_environment.name
    end
    names
  end

  def domain(fabric, network = nil)
    case fabric
    when 'local'
      case network
      when nil, :prod
        "#{@domain_suffix}"
      else
        "#{network}.#{@domain_suffix}"
      end
    else
      case network
      when nil, :prod
        "#{fabric}.#{@domain_suffix}"
      else
        "#{network}.#{fabric}.#{@domain_suffix}"
      end
    end
  end

  def environment
    self
  end

  def parent?
    !@parent.nil?
  end

  def cross_site_routing_required?
    return false if @primary_site.nil? || @secondary_site.nil?
    @primary_site != @secondary_site
  end

  def cross_site_routing(fabric, network = 'prod')
    fail "Un-supported cross site routing network #{network}" if network != 'prod'
    site = (fabric == @primary_site) ? @secondary_site : @primary_site
    {
      "networking::routing::to_site" => {
        'network' => network,
        'site'    => site
      }
    }
  end

  # rubocop:disable Style/TrivialAccessors
  def persistent_storage_supported?
    @persistent_storage_supported
  end
  # rubocop:enable Style/TrivialAccessors

  # rubocop:disable Style/TrivialAccessors
  def every_machine_destroyable?
    @every_machine_destroyable
  end
  # rubocop:enable Style/TrivialAccessors

  def env(name, options = {}, &block)
    @definitions[name] = Stacks::Environment.new(name, self.options.merge(options), self, @environments, @stack_procs)
    @children << @definitions[name]
    @definitions[name].instance_eval(&block) unless block.nil?
  end

  def instantiate_stack(stack_name)
    factory = @stack_procs[stack_name]
    fail "no stack found '#{stack_name}'" if factory.nil?
    instantiated_stack = factory.call(self)
    @definitions[instantiated_stack.name] = instantiated_stack
  end

  def contains_node_of_type?(clazz)
    found = false
    accept do |node|
      found = true if node.is_a?(clazz)
    end
    found
  end
end
