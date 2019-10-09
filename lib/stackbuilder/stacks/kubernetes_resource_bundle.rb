class Stacks::KubernetesResourceBundle
  attr_reader :site
  attr_reader :environment_name
  attr_reader :machine_set_name
  attr_reader :resources
  attr_reader :secrets

  def initialize(site, environment_name, stack_name, machine_set_name, labels, resources, secrets, hiera_scope)
    @site = site
    @environment_name = environment_name
    @stack_name = stack_name
    @machine_set_name = machine_set_name
    @resources = resources
    @secrets = secrets
    @hiera_scope = hiera_scope
    @labels = labels
  end

  def to_defns_yaml
    @resources.map do |k8s_defn|
      ZAMLS.to_zamls(k8s_defn)
    end.join("\n")
  end

  def apply_and_prune(mco_secrets_client)
    secret_resource = "#{@labels['app.kubernetes.io/name']}-secret"
    logger(Logger::INFO) { "Preparing #{@secrets.size} secrets for #{@machine_set_name} in resource #{secret_resource}" }
    logger(Logger::DEBUG) { "Secrets to load: #{@secrets.keys.join(', ')}" }
    responses = mco_secrets_client.insert(:namespace => @environment_name,
                                          :context => @site,
                                          :secret_resource => secret_resource,
                                          :labels => @labels.merge('app.kubernetes.io/managed-by' => 'mco-secretagent'),
                                          :keys => @secrets.keys,
                                          :scope => @hiera_scope)

    if responses.any? { |r| r.results[:statuscode] != 0 }
      responses.each do |r|
        logger(Logger::ERROR) { "#{r.results[:sender]} responded #{r.results[:statusmsg]}" }
      end
      fail "Failed to prepare secrets"
    else
      logger(Logger::INFO) { "Successfully prepared secrets" }
      responses.each do |r|
        logger(Logger::INFO) { r.results[:data][:output] }
      end
    end

    k8s_defns_yaml = to_defns_yaml
    command = ['apply',
               '--context', @site,
               '--prune',
               '-l', "stack=#{@stack_name},machineset=#{@machine_set_name},app.kubernetes.io/managed-by=stacks",
               '-f', '-']
    logger(Logger::DEBUG) { "running command: #{command.join(' ')}" }
    stdout_str, error_str, status = run_kubectl(*command, :stdin_data => k8s_defns_yaml)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to apply k8s resource definitions - error: #{error_str}"
    end
  end

  def clean
    kinds = (@resources.map { |r| r['kind'].downcase } + ['secret']).uniq.join(',')

    stdout_str, error_str, status = run_kubectl('delete',
                                                kinds,
                                                '--context',
                                                @site,
                                                '-l',
                                                "stack=#{@stack_name},machineset=#{@machine_set_name}",
                                                '-n', @environment_name)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to delete k8s resource definitions - error: #{error_str}"
    end
  end

  private

  def run_kubectl(*args)
    stdout_str, _error_str, _status = Open3.capture3('kubectl', 'version', '--context', @site, '-o', 'yaml')
    cmd_output_hash = YAML.load(stdout_str)
    client_version = cmd_output_hash['clientVersion']
    server_version = cmd_output_hash['serverVersion']

    if client_version['major'] < server_version['major'] ||
       (client_version['major'] == server_version['major']) && (client_version['minor'] < server_version['minor'])
      fail "Your kubectl version is out of date. Please update to at least version #{server_version['major']}.#{server_version['minor']}"
    end
    Open3.capture3('kubectl', *args)
  end
end
