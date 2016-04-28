module Stacks::Services::MongoDBCluster
  attr_accessor :application
  attr_accessor :supported_requirements

  def self.extended(object)
    object.configure
  end

  def configure
    @supported_requirements = :accept_any_requirement_default_all_servers
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
