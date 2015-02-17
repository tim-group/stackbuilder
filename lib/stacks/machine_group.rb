require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::MachineGroup
  def self.extended(object)
    object.configure()
  end

  def configure()
    on_bind do |machineset, environment|
      @environment = environment
      configure_domain_name(environment)
      self.instance_eval(&@config_block) unless @config_block.nil?
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
    environment.name + "-" + self.name
  end

  def instantiate_machines(environment)
    @instances.times do |i|
      index = sprintf("%03d", i + 1)
      @definitions["#{name}-#{index}"] = server = @type.new(self, index, &@config_block)
      if server.respond_to?(:group)
        server.group = groups[i % groups.size]
      end

      if server.respond_to?(:availability_group)
        server.availability_group = availability_group(environment)
      end
    end
  end
end
