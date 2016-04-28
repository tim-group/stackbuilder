module Stacks::Services::MongoDBCluster
  attr_accessor :database_name
  attr_accessor :supported_requirements
  attr_accessor :master_instances
  attr_accessor :arbiter_instances
  attr_accessor :backup_instances
  def self.extended(object)
    object.configure
  end

  def configure
    @supported_requirements = :accept_any_requirement_default_all_servers
    @master_instances = 2
    @backup_instances = 1
    @arbiter_instances = 1
    @database_name = ''
  end

  def instantiate_machines(environment)
    i = 0
    @master_instances.times do
      instantiate_machine(name, :master, i += 1, environment, :primary_site)
    end
    i = 0
    @arbiter_instances.times do
      instantiate_machine(name, :arbiter, i += 1, environment, :primary_site)
    end
    i = 0
    @backup_instances.times do
      instantiate_machine(name, :backup, i += 1, environment, :secondary_site)
    end
  end

  def instantiate_machine(name, type, i, environment, location)
    index = sprintf("%03d", i)
    server_name = "#{name}-#{index}"
    server_name = "#{name}#{type}-#{index}" if [:backup, :arbiter].include?(type)
    server = @type.new(server_name, i, self, type, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions["#{server_name}-#{location}"] = server
  end

  def requirement_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.find { |dependency| dependency[0] == name }
    fail "Stack '#{dependant.name}' must specify requirement when using depend_on #{name} "\
          "in environment '#{environment.name}'. Usage: depend_on <environment>, <requirement>" \
          if dependent_on_this_cluster[2].nil?
    dependent_on_this_cluster[2]
  end

  def config_params(dependent, _fabric)
    acceptable_supported_requirements = [:accept_any_requirement_default_all_servers]
    fail "Stack '#{name}' invalid supported requirements: #{supported_requirements} "\
          "in environment '#{environment.name}'. Acceptable supported requirements: "\
          "#{acceptable_supported_requirements}." \
          unless acceptable_supported_requirements.include?(@supported_requirements)

    config_properties(dependent, children.map(&:prod_fqdn))
  end

  def config_properties(dependent, fqdns)
    requirement = requirement_of(dependent)
    config_params = {
      "#{requirement}.mongodb.enabled" => 'true',
      "#{requirement}.mongodb.server_fqdns" => fqdns.sort.join(','),
      "#{requirement}.mongodb.username" => dependent.application,
      "#{requirement}.mongodb.password_hiera_key" =>
        "enc/#{dependent.environment.name}/#{dependent.application}/mongodb_#{requirement}_password"
    }
    config_params
  end
end
