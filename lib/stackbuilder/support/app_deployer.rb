require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_deployapp'

class Support::AppDeployer
  def initialize
    @deployapp = Support::MCollectiveDeployapp.new
  end

  def deploy_applications(machine_def)
    valid = false
    env_name = machine_def.environment.name

    if machine_def.is_a? Stacks::Services::AppServer
      valid = true
      install_and_start_application(env_name, machine_def.mgmt_fqdn, machine_def.virtual_service.application)
    else
      targets = Set.new
      machine_def.accept do |child_machine_def|
        if child_machine_def.is_a? Stacks::Services::AppServer
          valid = true
          targets << { :app => child_machine_def.virtual_service.application, :fqdn => child_machine_def.mgmt_fqdn }
        end
      end
      targets.to_a.each do |target|
        install_and_start_application(env_name, target[:fqdn], target[:app])
      end
    end

    logger(Logger::INFO) { "machine_def \"#{machine_def.name}\" has no application to start" } unless valid
  end

  def query_cmdb_for(spec)
    cmdb_repo_url = 'http://git/cmdb' # TODO: parameterise?

    require 'tmpdir'
    cmdb_dir = Dir.mktmpdir

    unless system("git clone --quiet --depth 1 '#{cmdb_repo_url}' '#{cmdb_dir}'")
      fail "Unable to clone '#{cmdb_repo_url}'"
    end

    require 'yaml'
    cmdb = YAML.load(File.open("#{cmdb_dir}/#{spec[:environment]}/#{spec[:application]}.yaml")).map do |el|
      Hash[el.map { |(k, v)| [k.to_sym, v] }]
    end

    logger(Logger::DEBUG) { "cmdb data: #{cmdb}" }
    result = cmdb.detect { |group| group[:name] == spec[:group] }

    fail "No CMDB data for #{spec}" unless result
    result
  ensure
    FileUtils.remove_entry(cmdb_dir)
  end

  private

  def install_and_start_application(environment, fqdn, app_name)
    spec = {
      :application => app_name,
      :environment => environment
    }
    logger(Logger::INFO) { "Installing application on #{fqdn} : #{spec}" }

    status = @deployapp.get_application_status(fqdn, spec)

    fail "Application is already present" if status[:present]

    spec[:group] = status[:group]
    cmdb = query_cmdb_for(spec)

    @deployapp.deploy_app_version(fqdn, spec, cmdb[:target_version])

    wait_for_healthy(fqdn, spec)

    @deployapp.enable_participation(fqdn, spec) if cmdb[:target_participation]
  end

  def wait_for_healthy(fqdn, spec)
    logger(Logger::INFO) { "Waiting for healthy app on #{fqdn} : #{spec}" }
    timeout = 25 * 60
    start_time = Time.now
    while @deployapp.get_application_status(fqdn, spec)[:health] != 'healthy' && Time.now - start_time < timeout
      sleep 5
    end
    fail "App did not go healthy in time" unless @deployapp.get_application_status(fqdn, spec)[:health] == 'healthy'
  end
end
