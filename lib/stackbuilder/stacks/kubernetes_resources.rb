class Stacks::KubernetesResources
  attr_reader :site
  attr_reader :resources
  attr_reader :secrets

  def initialize(site, environment, stack_name, machine_set_name, labels, resources, secrets, hiera_scope)
    @site = site
    @environment = environment
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
    responses = mco_secrets_client.insert(:namespace => @environment,
                                          :context => @site,
                                          :secret_resource => secret_resource,
                                          :labels => @labels,
                                          :keys => @secrets.keys,
                                          :scope => @hiera_scope)

    if responses.any? { |r| r.results[:statuscode] != 0 }
      responses.each do |r|
        logger(Logger::ERROR) { "#{r.results[:sender]} responded #{r.results[:statusmsg]}" }
      end
      fail "Failed to prepare secrets"
    else
      logger(Logger::INFO) { "Successfully prepared secrets" }
    end

    k8s_defns_yaml = to_defns_yaml
    command = ['kubectl', 'apply',
               '--context', @site,
               '--prune',
               '-l', "stack=#{@stack_name},machineset=#{@machine_set_name}",
               '-f', '-']
    logger(Logger::DEBUG) { "running command: #{command.join(' ')}" }
    stdout_str, error_str, status = Open3.capture3(*command, :stdin_data => k8s_defns_yaml)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to apply k8s resource definitions - error: #{error_str}"
    end
  end

  def clean
    kinds = @resources.map { |r| r['kind'].downcase }.uniq.join(',')

    stdout_str, error_str, status = Open3.capture3('kubectl',
                                                   'delete',
                                                   kinds,
                                                   '--context',
                                                   @site,
                                                   '-l',
                                                   "stack=#{@stack_name},machineset=#{@machine_set_name}",
                                                   '-n', @environment)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to delete k8s resource definitions - error: #{error_str}"
    end
  end
end
