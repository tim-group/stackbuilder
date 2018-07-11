require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def_container'

class Stacks::Environment
  attr_reader :domain_suffix
  attr_reader :environments # XXX this is silly and leads to an infinite data structure
  attr_reader :parent
  attr_reader :name
  attr_reader :options
  attr_reader :primary_site
  attr_reader :secondary_site
  attr_accessor :production
  attr_reader :routes
  attr_reader :sites
  attr_accessor :allocation_tags
  attr_reader :depends_on

  include Stacks::MachineDefContainer

  def initialize(name, options, parent, environments, stack_procs, calculated_dependencies_cache)
    @name = name
    @options = options
    @environments = environments
    @stack_procs = stack_procs
    @definitions = {}
    @every_machine_destroyable =
      options[:every_machine_destroyable].nil? ? false : options[:every_machine_destroyable]
    @primary_site = options[:primary_site]
    @secondary_site = options[:secondary_site]

    # Transitional site lookup array, allowing servers to translate sites (oy,pg) to legacy symbols
    @sites = [options[:primary_site], options[:secondary_site]]

    @domain_suffix = options[:domain_suffix] || 'net.local'
    @parent = parent
    @children = []
    @production = options[:production].nil? ? false : options[:production]
    @calculated_dependencies_cache = calculated_dependencies_cache
    @allocation_tags = { @primary_site => [] }
    @allocation_tags[@secondary_site] = [] unless @secondary_site.nil?

    @routes = { @primary_site   => [] }
    @routes[@secondary_site] = [] unless @secondary_site.nil?
    @routes.keys.each do |site|
      @routes[site].concat(@parent.routes[site]) if @parent.routes.key?(site)
    end unless @parent.nil?
    @depends_on = []
  end

  # Transitional site lookup array, allowing servers to translate sites (oy,pg) to legacy symbols
  def translate_site_symbol(site)
    return :primary_site   if @sites.find_index(site) == 0
    return :secondary_site if @sites.find_index(site) == 1
    fail "Environment: #{environment.name} does not support site: #{site}. Environment is only available in: #{@sites.join(',')}"
  end

  def validate_instance_sites(requested_sites)
    site_diff = requested_sites - @sites
    fail "#{name} environment does not support site(s): #{site_diff.join(',')}" \
         "\nSites requested: #{requested_sites}" \
         "\nEnvironment provides: #{@sites}" unless site_diff.empty?
  end

  def add_route(fabric, route_name)
    @routes[fabric] << route_name unless @routes[fabric].include? route_name
  end

  def set_allocation_tags(fabric, tags)
    @allocation_tags[fabric] = tags
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

  def domain(site, network = nil)
    case site
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
        "#{site}.#{@domain_suffix}"
      else
        "#{network}.#{site}.#{@domain_suffix}"
      end
    end
  end

  def environment
    self
  end

  def type_of?
    :environment
  end

  def identity
    name.to_sym
  end

  def all_environments
    @environments.inject([]) do |acc, (_, env)|
      add_sub_environments(acc, top_level_env_of(env))
      acc
    end.inject({}) do |map, env|
      map[env.name] = env
      map
    end
  end

  def add_sub_environments(accumulator, env)
    accumulator << env
    env.sub_environments.inject(accumulator) do |acc, sub|
      add_sub_environments(acc, sub)
      acc
    end
  end

  def top_level_env_of(e)
    if e.parent.nil?
      e
    else
      highest_environment(e.parent)
    end
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
      'networking::routing::to_site' => {
        'network' => network,
        'site'    => site
      }
    }
  end

  def every_machine_destroyable?
    @every_machine_destroyable
  end

  def env(name, options = {}, &block)
    @definitions[name] = Stacks::Environment.new(
      name,
      self.options.merge(options),
      self,
      @environments,
      @stack_procs,
      @calculated_dependencies_cache)
    @children << @definitions[name]
    @definitions[name].instance_eval(&block) unless block.nil?
  end

  def find_environment(environment_name)
    env = environment.find_all_environments.select do |environment|
      environment.name == environment_name
    end
    if env.size == 1
      return env.first
    else
      fail "Cannot find environment '#{environment_name}'"
    end
  end

  def find_all_environments
    environment_set = Set.new
    environment.environments.values.each do |env|
      unless environment_set.include? env
        environment_set.merge(env.children)
        environment_set.add(env)
      end
    end
    environment_set
  end

  def virtual_services
    virtual_services = []
    find_all_environments.each do |env|
      env.accept do |virtual_service|
        virtual_services.push virtual_service
      end
    end
    virtual_services
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

  def find_stacks(name)
    nodes = []
    accept do |machine_def|
      if (machine_def.respond_to?(:mgmt_fqdn) && machine_def.mgmt_fqdn == name) || machine_def.name == name
        nodes.push(machine_def)
      end
    end
    nodes
  end

  def calculated_dependencies
    @calculated_dependencies_cache.get
  end

  def lookup_dependency(dependency_id)
    @calculated_dependencies_cache.lookup(dependency_id, find_all_environments)
  end

  def depend_on(dependant, env = environment.name, requirement = nil)
    fail('Dependant cannot be nil') if dependant.nil? || dependant.eql?('')
    fail('Environment cannot be nil') if env.nil? || env.eql?('')
    @depends_on << [dependant, env, requirement] unless @depends_on.include? [dependant, env, requirement]
  end
end
