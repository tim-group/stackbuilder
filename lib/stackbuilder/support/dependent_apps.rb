require 'stackbuilder/support/namespace'

DependentAppMcoCommand = Struct.new(:environment, :application, :group, :mco_service_command) do
  def describe
    executable
  end

  def executable
    service_name = "#{environment}-#{application}-#{group}"
    mco_filters = "-F logicalenv=#{environment} -F application=#{application} -F group=#{group}"
    "mco service #{service_name} #{mco_service_command} #{mco_filters}"
  end
end

DependentAppKubectlCommand = Struct.new(:deployment, :environment, :site) do
  def describe
    executable
  end

  def executable
    "kubectl --context=#{site} -n #{environment} scale deploy #{deployment} --replicas=0"
  end
end

DependentAppStacksApplyCommand = Struct.new(:environment, :stack) do
  def describe
    start_cmd = "stacks -e #{environment} -s #{stack} apply"
    "[equivalent of: `#{start_cmd}`]"
  end
end

class Support::DependentApps
  def initialize(environment, dependency)
    @environment = environment
    @dependency = dependency
  end

  def unsafely_stop_commands
    @dependency.virtual_services_that_depend_on_me.
      select { |dependent| dependent.is_a? Stacks::Services::AppService }.
      map do |dependent|
      if dependent.kubernetes
        sites = if dependent.instances.is_a?(Hash)
                  dependent.instances.keys
                else
                  [@environment.sites.first]
                end
        sites.map { |site| DependentAppKubectlCommand.new(dependent.k8s_app_resources_name, @environment.name, site) }
      else
        dependent.groups.map do |group|
          DependentAppMcoCommand.new(@environment.name, dependent.application, group, "stop")
        end
      end
    end.flatten.to_set
  end

  def unsafely_start_commands
    @dependency.virtual_services_that_depend_on_me.
      select { |dependent| dependent.is_a? Stacks::Services::AppService }.
      map do |dependent|
      if dependent.kubernetes
        DependentAppStacksApplyCommand.new(dependent.environment.name, dependent.name)
      else
        dependent.groups.map do |group|
          DependentAppMcoCommand.new(@environment.name, dependent.application, group, "start")
        end
      end
    end.flatten.uniq.to_set
  end
end
