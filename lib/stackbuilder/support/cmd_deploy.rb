module CMDDeploy
  def do_deploy_applications(machine_def)
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

  private

  def install_and_start_application(environment, fqdn, app_name)
    spec = {
      :application => app_name,
      :environment => environment
    }
    logger(Logger::INFO) { "Installing application on #{fqdn} : #{spec}" }

    status = get_application_status(fqdn, spec)

    fail "Application is already present" if status[:present]

    spec[:group] = status[:group]
    cmdb = query_cmdb_for(spec)

    deploy_app_version(fqdn, spec, cmdb[:target_version])

    wait_for_healthy(fqdn, spec)

    enable_participation(fqdn, spec) if cmdb[:target_participation]
  end

  def get_application_status(fqdn, spec)
    statuses = mco_client("deployapp", :nodes => [fqdn]) do |mco|
      mco.status(:spec => spec).map do |response|
        fail response[:statusmsg] unless response[:statuscode] == 0
        log_deployapp_response(response)
        fail response[:data] unless response[:data][:successful]
        response[:data][:statuses]
      end
    end.flatten
    fail "could not determine application status: #{statuses}" unless statuses.length == 1
    statuses[0]
  end

  def deploy_app_version(fqdn, spec, version)
    logger(Logger::INFO) { "Deploying app version #{version} on #{fqdn} : #{spec}" }
    mco_client("deployapp", :nodes => [fqdn]) do |mco|
      mco.update_to_version(:spec => spec, :version => version).map do |response|
        fail response[:statusmsg] unless response[:statuscode] == 0
        log_deployapp_response(response)
        fail response[:data] unless response[:data][:successful]
      end
    end
  end

  def enable_participation(fqdn, spec)
    logger(Logger::INFO) { "Enabling participation app on #{fqdn} : #{spec}" }
    mco_client("deployapp", :nodes => [fqdn]) do |mco|
      mco.enable_participation(:spec => spec).map do |response|
        fail response[:statusmsg] unless response[:statuscode] == 0
        log_deployapp_response(response)
        fail response[:data] unless response[:data][:successful]
      end
    end
  end

  def log_deployapp_response(response)
    if response[:data] && response[:data][:logs]
      logs = response[:data][:logs]
      logs[:debugs].each { |msg| logger(Logger::DEBUG) { msg } } if logs[:debugs]
      logs[:infos].each { |msg| logger(Logger::INFO) { msg } } if logs[:infos]
      logs[:warns].each { |msg| logger(Logger::WARN) { msg } } if logs[:warns]
      logs[:errors].each { |msg| logger(Logger::ERROR) { msg } } if logs[:errors]
    else
      logger(Logger::WARN) { "no logs from mco deployapp call" }
    end
  end

  def wait_for_healthy(fqdn, spec)
    logger(Logger::INFO) { "Waiting for Healthy app on #{fqdn} : #{spec}" }
    timeout = 25 * 60
    start_time = Time.now
    while get_application_status(fqdn, spec)[:health] != 'healthy' && Time.now - start_time < timeout
      sleep 5
    end
  end

  def query_cmdb_for(spec)
    cmdb_repo_url = 'http://git/cmdb' # TODO: parameterise?

    require 'tmpdir'
    cmdb_dir = Dir.mktmpdir

    if !system("git clone --quiet --depth 1 '#{cmdb_repo_url}' '#{cmdb_dir}'")
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
end
