require 'stackbuilder/support/zamls'

class Stacks::KubernetesResourceBundle
  attr_reader :site
  attr_reader :environment_name
  attr_reader :machine_set_name
  attr_reader :resources
  attr_reader :secrets

  def initialize(site, environment_name, labels, resources, secrets, hiera_scope, secret_name)
    @site = site
    @environment_name = environment_name
    @stack_name = labels['stack']
    @machine_set_name = labels['machineset']
    @resources = resources
    @secrets = secrets
    @hiera_scope = hiera_scope
    @labels = labels
    @secret_name = secret_name
  end

  def to_defns_yaml
    @resources.map do |k8s_defn|
      ZAMLS.to_zamls(k8s_defn)
    end.join("\n")
  end

  def apply_and_prune(mco_secrets_client)
    logger(Logger::INFO) { "Preparing #{@secrets.size} secrets for #{@machine_set_name} in resource #{@secret_name}" }
    logger(Logger::DEBUG) { "Secrets to load: #{@secrets.keys.join(', ')}" }
    responses = mco_secrets_client.insert(:namespace => @environment_name,
                                          :context => @site,
                                          :secret_resource => @secret_name,
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

    prune_whitelist = [
      '/v1/ConfigMap',
      'apps/v1/Deployment',
      'networking.k8s.io/v1beta1/Ingress',
      'networking.k8s.io/v1/NetworkPolicy',
      'rbac.authorization.k8s.io/v1beta1/Role',
      'rbac.authorization.k8s.io/v1/Role',
      'rbac.authorization.k8s.io/v1beta1/RoleBinding',
      'rbac.authorization.k8s.io/v1/RoleBinding',
      '/v1/Service',
      '/v1/ServiceAccount',
      'monitoring.coreos.com/v1/PrometheusRule',
      'policy/v1beta1/PodDisruptionBudget',
      'traefik.containo.us/v1alpha1/IngressRouteUDP',
      'batch/v1beta1/CronJob'
    ]

    rest_mappings_found = @resources.map { |r| r['apiVersion'].include?('/') ? "#{r['apiVersion']}/#{r['kind']}" : "/#{r['apiVersion']}/#{r['kind']}" }

    unexpected_rest_mappings = rest_mappings_found - prune_whitelist
    if unexpected_rest_mappings.size > 0
      fail "Found new resource type(s) (#{unexpected_rest_mappings.join(', ')}) that is not in the prune whitelist. Please add it."
    end

    k8s_defns_yaml = to_defns_yaml

    command = ['apply',
               '--context', @site,
               '--prune',
               '-l', "stack=#{@stack_name},machineset=#{@machine_set_name},app.kubernetes.io/managed-by=stacks"
              ] +
              prune_whitelist.map { |m| ['--prune-whitelist', m] }.flatten +
              ['-f', '-']
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

  def check_deployment_version
    deployment = @resources.find { |r| r['kind'] == 'Deployment' && r['metadata']['labels']['app.kubernetes.io/component'] == 'app_service' }
    stdout_str, _stderr_str, _status = run_kubectl('get',
                                                   '--context', @site,
                                                   '--namespace', @environment_name,
                                                   'deployments.app', deployment['metadata']['name'],
                                                   '-o', 'jsonpath={.metadata.labels.app\.kubernetes\.io/version}')

    expected_version = deployment['metadata']['labels']['app.kubernetes.io/version']

    fail "Deployment version unexpected: checking deployment of #{expected_version} but found version #{stdout_str} deployed" \
      if stdout_str != expected_version
  end

  def wait_and_check_deployment
    check_deployment_version

    deployment = @resources.find { |r| r['kind'] == 'Deployment' && r['metadata']['labels']['app.kubernetes.io/component'] == 'app_service' }

    logger(Logger::INFO) { "Waiting for #{deployment['metadata']['name']} to complete" }
    stdout_str, stderr_str, status = run_kubectl('rollout', 'status',
                                                 '--context', @site,
                                                 '--namespace', @environment_name,
                                                 'deployments.app', deployment['metadata']['name'])

    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to deploy - error: #{stderr_str}"
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
