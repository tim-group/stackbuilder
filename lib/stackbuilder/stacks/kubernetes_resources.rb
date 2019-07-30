class Stacks::KubernetesResources
  include Enumerable

  def initialize(stack_name, machine_set_name, resources, secrets, hiera_scope)
    @stack_name = stack_name
    @machine_set_name = machine_set_name
    @resources = resources
    @secrets = secrets
    @hiera_scope = hiera_scope
  end

  def each
    @resources.each { |r| yield r }
  end

  def to_defns_yaml
    @resources.map do |k8s_defn|
      ZAMLS.to_zamls(k8s_defn)
    end.join("\n")
  end

  def apply_and_prune
    k8s_defns_yaml = to_defns_yaml
    command = ['kubectl', 'apply', '--prune', '-l', "stack=#{@stack_name},machineset=#{@machine_set_name}", '-f', '-']
    logger(Logger::DEBUG) { "running command: #{command.join(' ')}" }
    stdout_str, error_str, status = Open3.capture3(*command, :stdin_data => k8s_defns_yaml)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to apply k8s resource definitions - error: #{error_str}"
    end
  end
end
