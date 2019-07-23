require 'stackbuilder/support/zamls'
require 'stackbuilder/support/audit_site'
require 'stackbuilder/support/audit_vms'
require 'stackbuilder/support/env_listing'
require 'stackbuilder/support/live_migration'
require 'stackbuilder/support/host_builder'
require 'stackbuilder/support/dns_resolver'
require 'stackbuilder/support/mcollective'
require 'open3'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
class CMD
  attr_reader :cmds # this list is just a safety check
  attr_reader :read_cmds # this list is just a safety check
  attr_reader :write_cmds # this list is just a safety check

  # rubocop:disable Metrics/ParameterLists
  def initialize(factory, core_actions, dns, nagios, subscription, puppet, app_deployer, dns_resolver,
                 hiera_provider, cleaner, environment, stack_name = nil, stash = false)
    @factory = factory
    @core_actions = core_actions
    @dns = dns
    @nagios = nagios
    @subscription = subscription
    @puppet = puppet
    @app_deployer = app_deployer
    @dns_resolver = dns_resolver
    @hiera_provider = hiera_provider
    @cleaner = cleaner
    @environment = environment
    @stack_name = stack_name
    @stash = stash
    @read_cmds = %w(audit audit_vms compile dependencies dependents diff sbdiff ls lsenv enc spec terminus test showvnc check_definition)
    @write_cmds = %w(dns clean clean_all launch allocate provision reprovision move clear_host rebuild_host build_new_host)
    @cmds = @read_cmds + @write_cmds
  end
  # rubocop:enable Metrics/ParameterLists

  # dump all the info from stackbuilder-config into one file, to enable manipulation with external tools.
  # use yaml, as that's what puppet reads in
  def compile(_argv)
    puts generate_compile_output
  end

  def diff(_argv)
    diff_tool = ENV['DIFF'] || '/usr/bin/sdiff -s'
    sbc_path = @factory.path
    logger(Logger::DEBUG) { "Using sbc_path: #{sbc_path}" }

    require 'tempfile'
    before_file = Tempfile.new('before')
    after_file = Tempfile.new('after')

    Dir.chdir(sbc_path) do
      system("git diff --quiet") # returns 0 if working tree clean, 1 if dirty
      if $CHILD_STATUS.to_i == 0
        system("git checkout HEAD~1")
        @factory.refresh
        before_file.write(generate_compile_output)
        system("git checkout -")
        @factory.refresh
        after_file.write(generate_compile_output)
      else
        fail('Stackbuilder-config working tree not clean. Commit your changes or use --stash') unless @stash
        after_file.write(generate_compile_output)
        system("git stash")
        @factory.refresh
        before_file.write(generate_compile_output)
        system("git stash pop --index")
      end
    end
    system("#{diff_tool} #{before_file.path} #{after_file.path}") if $CHILD_STATUS.to_i == 0
    before_file.unlink
    after_file.unlink
  end

  def sbdiff(_argv)
    diff_tool = ENV['DIFF'] || '/usr/bin/sdiff -s'

    require 'tempfile'
    before_file = Tempfile.new('before')
    after_file = Tempfile.new('after')
    system("sudo apt-get install stackbuilder && stacks compile > #{before_file.path}")
    system("rake package install && stacks compile > #{after_file.path}") if $CHILD_STATUS.to_i == 0
    system("#{diff_tool} #{before_file.path} #{after_file.path}") if $CHILD_STATUS.to_i == 0
    before_file.unlink
    after_file.unlink
  end

  def terminus(_argv)
    output = {}
    @factory.inventory.environments.sort.each do |_envname, env|
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        box_id = "#{stack.hostname}.mgmt.#{stack.domain}" # puppet refers to our hosts using the 'mgmt' name
        output[box_id] = stack.to_enc
      end
    end
    puts ZAMLS.to_zamls(output)
  end

  def enc(_argv)
    machine_def = check_and_get_stack

    if machine_def.respond_to?(:to_enc)
      puts ZAMLS.to_zamls(machine_def.to_enc)
    else
      logger(Logger::FATAL) { "\"#{@stack_name}\" is not a machine fqdn" }
      fail "Machine not found"
    end
  end

  def spec(_argv)
    machine_def = check_and_get_stack

    if machine_def.respond_to?(:to_spec)
      puts ZAMLS.to_zamls(machine_def.to_spec)
    else
      logger(Logger::FATAL) { "\"#{@stack_name}\" is not a machine fqdn" }
      fail "Machine not found"
    end
  end

  def dns(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'dns needs a subcommand' }
      fail 'Subcommand not provided'
    end

    machine_def = check_and_get_stack

    case cmd
    when 'allocate_ips'
      @dns.do_allocate_ips(machine_def)
    when 'free_ips'
      @dns.do_free_ips(machine_def)
    when 'allocate_vips'
      @dns.do_allocate_vips(machine_def)
    when 'free_vips'
      @dns.do_free_vips(machine_def)
    else
      logger(Logger::FATAL) { "invalid sub command \"#{cmd}\"" }
      fail 'Unknown subcommand'
    end
  end

  def nagios(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'nagios needs a subcommand' }
      fail 'Subcommand not provided'
    end

    machine_def = check_and_get_stack

    case cmd
    when 'disable'
      @nagios.nagios_schedule_downtime(machine_def)
    when 'enable'
      @nagios.nagios_cancel_downtime(machine_def)
    else
      logger(Logger::FATAL) { "invalid command \"#{cmd}\"" }
      fail 'Unknown subcommand'
    end
  end

  def test(_argv)
    machine_def = check_and_get_stack

    require 'rspec'
    RSpec::Core::Runner.disable_autorun!

    specs_home = File.dirname(__FILE__) + "/../stacks/stacktests"

    machine_def.accept do |child_machine_def|
      specpath = "#{specs_home}/#{child_machine_def.clazz}/*.rb"
      RSpec.describe "#{child_machine_def.clazz}.#{child_machine_def.name}" do
        Dir[specpath].each do |file|
          require file
          test = File.basename(file, '.rb')
          it_behaves_like test, child_machine_def
        end
      end
    end

    result = RSpec::Core::Runner.run([], $stderr, $stdout)
    if (result != 0)
      logger(Logger::ERROR) do
        "The 'test' task failed, indicating the stack is not functioning correctly. " \
              "See the above test output for details."
      end
      fail "Error running tests"
    end
    result
  end

  def ls(_argv)
    Support::EnvListing.new($options[:terse]).ls(@stack_name ? check_and_get_stack : @environment)
  end

  def lsenv(_argv)
    Support::EnvListing.new($options[:terse]).ls(@environment.environments.values, true)
  end

  def audit(_argv)
    site = @environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{@environment.name}\" is \"#{site}\"" }
    Support::AuditSite.new(@factory.host_repository).audit(site)
  end

  def audit_vms(argv)
    auditor = Support::AuditVms.new(@factory)
    if argv.size == 0
      site = @environment.options[:primary_site]
      logger(Logger::DEBUG) { ":primary_site for \"#{@environment.name}\" is \"#{site}\"" }
      auditor.audit_site_vms(site, $options[:'diffs-only'], $options[:'ignore-safe-diffs'])
    else
      host_fqdn = argv[0]
      auditor.audit_host_vms(host_fqdn, $options[:'diffs-only'], $options[:'ignore-safe-diffs'])
    end
  end

  def clean(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def)
    0
  end

  def clean_all(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def, true)
    0
  end

  def launch(_argv)
    machine_def = check_and_get_stack
    @core_actions.get_action("launch").call(@factory.services, machine_def)
  end

  def allocate(_argv)
    machine_def = check_and_get_stack
    @core_actions.get_action("allocate").call(@factory.services, machine_def)
  end

  def check_definition(_argv)
    machine_def = check_and_get_stack
    specs = machine_def.flatten.map(&:to_spec)
    fabric_grouped_specs = specs.group_by { |spec| spec[:fabric] }
    fabric_grouped_specs.map do |fabric, fabric_specs|
      hosts = @factory.host_repository.find_compute_nodes(fabric, false, false, false)

      host_fqdn_by_machine_name = Hash[hosts.map do |host|
        host.allocated_machines.map do |machine|
          [machine[:hostname], host.fqdn]
        end
      end.flatten(1)]

      host_grouped_specs = fabric_specs.group_by { |spec| host_fqdn_by_machine_name[spec[:hostname]] }
      host_grouped_specs.each do |host_fqdn, host_specs|
        if host_fqdn.nil?
          host_specs.each { |spec| puts "[0;31m#{spec[:hostname]} ==> failed (not provisioned)[0m" }
        else
          results = @factory.compute_node_client.check_vm_definitions(host_fqdn, host_specs)
          results.each do |host_result|
            sender = host_result[0]
            host_result[1].each do |vm_name, vm_result|
              colour = vm_result[0] == 'success' ? "[0;32m" : "[0;31m"
              puts "#{colour}#{vm_name} ==> #{vm_result[0]} (on host #{sender})[0m"
              puts "  #{vm_result[1].gsub("\n", "  \n")}" unless vm_result[0] == 'success'
            end
          end
        end
      end
    end
  end

  def provision(_argv)
    thing = check_and_get_stack
    k8s_targets, vm_targets = split_k8s_from_vms(thing) do |x|
      if x.is_a?(Stacks::CustomServices)
        x.children
      else
        [x]
      end
    end

    k8s_targets.each do |t|
      @dns.do_allocate_vips(t)
      @puppet.do_puppet_run_on_dependencies(t)

      apply_k8s(t, t.stack.name)
    end

    vm_targets.each do |t|
      provision_vm(@factory.services, t)
    end
  end

  def reprovision(_argv)
    thing = check_and_get_stack

    k8s_targets, vm_targets = split_k8s_from_vms(thing) do |x|
      if x.is_a?(Stacks::CustomServices)
        x.children
      else
        [x]
      end
    end

    k8s_targets.each do |t|
      apply_k8s(t, t.stack.name)
    end

    vm_targets.each do |t|
      reprovision_vm(@factory.services, t)
    end

    0
  end

  def move(_argv)
    machines = check_and_get_stack.flatten

    if machines.size != 1
      logger(Logger::FATAL) { "moving more than one machine not supported" }
      fail "Too many machines selected"
    end

    machine = machines.first
    hosts = @factory.host_repository.find_compute_nodes(machine.fabric, false, false, false)
    host = hosts.find { |h| h.allocated_machines.map { |m| m[:hostname] }.include?(machine.hostname) }

    if host.nil?
      logger(Logger::FATAL) { "#{machine.hostname} is not provisioned" }
      fail "Machine not found"
    end

    Support::LiveMigrator.new(@factory, host).move(machine)
  end

  def clear_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to clear" }
      fail "Host not specified"
    end

    host_fqdn = argv[0]
    host = @factory.host_repository.find_compute_node(host_fqdn, false, false, false)

    if host.nil?
      logger(Logger::FATAL) { "unable to find #{host_fqdn}" }
      fail "Host not found"
    end

    Support::LiveMigrator.new(@factory, host).move_all
  end

  def rebuild_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to rebuild" }
      fail "No host specified"
    end

    Support::HostBuilder.new(@factory, @nagios, @puppet).rebuild(argv[0])
  end

  def build_new_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to rebuild" }
      fail "Host not specified"
    end

    Support::HostBuilder.new(@factory, @nagios, @puppet).build_new(argv[0])
  end

  def dependencies(_argv)
    machine_def = ensure_is_machine(check_and_get_stack)
    puts ZAMLS.to_zamls(machine_def.dependency_nodes.map(&:identity))
  end

  def dependents(_argv)
    machine_def = ensure_is_machine(check_and_get_stack)

    service_dependencies = machine_def.virtual_service.virtual_services_that_depend_on_me
    dependencies = service_dependencies.map { |machine_set| machine_set.children.map(&:identity) }.flatten
    puts ZAMLS.to_zamls(dependencies)
  end

  def showvnc(_argv)
    machine_def = check_and_get_stack

    hosts = []
    machine_def.accept do |child|
      hosts << child.name if child.is_a? Stacks::MachineDef
    end

    self.class.include Support::MCollective
    mco_client("libvirt") do |mco|
      mco.fact_filter "domain=/(st|ci)/"
      results = {}
      hosts.each do |host|
        mco.domainxml(:domain => host) do |result|
          xml = result[:body][:data][:xml]
          sender = result[:senderid]
          unless xml.nil?
            matches = /type='vnc' port='(\-?\d+)'/.match(xml)
            fail "Pattern match for vnc port was nil for #{host}\n XML output:\n#{xml}" if matches.nil?
            fail "Pattern match for vnc port contains no captures for #{host}\n XML output:\n#{xml}" \
                  if matches.captures.empty?
            results[host] = {
              :host => sender,
              :port => matches.captures.first
            }
          end
        end
      end
      results.each do |vm, location|
        puts "#{vm}  -> #{location[:host]}:#{location[:port]}"
      end
    end
  end

  private

  def generate_compile_output
    vm_targets = []
    k8s_targets = []

    if @stack_name.nil?
      @factory.inventory.environments.sort.each do |_envname, env|
        vm_targets += env.flatten
        env.accept do |c|
          if c.is_a?(Stacks::CustomServices)
            k8s_targets += c.k8s_machinesets.values.flatten
          end
        end
      end
    else
      thing = check_and_get_stack
      k8s_targets, vm_targets = split_k8s_from_vms(thing) { |x| x.flatten }
    end

    [vms_compile_output(vm_targets), k8s_compile_output(k8s_targets)].compact.join("\n")
  end

  def ensure_is_machine(machine_def)
    if !machine_def.is_a?(Stacks::MachineDef)
      logger(Logger::FATAL) { "\"#{@stack_name}\" is not a machine fqdn" }
      fail "Machine not found"
    end
    machine_def
  end

  def check_and_get_stack
    if @stack_name.nil?
      logger(Logger::FATAL) { 'option "stack" not set' }
      fail "Internal error"
    end

    stacks = []
    @environment.accept do |thing|
      if (thing.respond_to?(:mgmt_fqdn) && thing.mgmt_fqdn == @stack_name) || thing.name == @stack_name
        stacks.push(thing)
      end
      if thing.is_a?(Stacks::CustomServices)
        thing.k8s_machinesets.values.each do |set|
          set.accept do |machine_def|
            if (machine_def.respond_to?(:mgmt_fqdn) && machine_def.mgmt_fqdn == @stack_name) || machine_def.name == @stack_name
              stacks.push(machine_def)
            end
          end
        end
      end
    end

    if stacks.empty?
      logger(Logger::FATAL) { "stack \"#{@stack_name}\" not found" }
      fail "Entity not found"
    end

    if stacks.size > 1
      names = stacks.map { |s| s.respond_to?(:mgmt_fqdn) ? s.mgmt_fqdn : s.name }
      logger(Logger::FATAL) { "Multiple stacks match specified stack name (#{names.join(', ')})." }
      fail "Too many entities found"
    end

    thing = stacks.first

    if thing.is_a?(Stacks::MachineDef) && thing.virtual_service && thing.virtual_service.kubernetes
      logger(Logger::FATAL) { "Cannot operate on a single host for kubernetes. Use the stack or service (#{thing.virtual_service.name}) instead" }
      fail "Invalid selection. Cannot use machinedef for kubernetes"
    end

    thing
  end

  def split_k8s_from_vms(thing, &vm_extraction)
    vm_extraction ||= lambda { |x| [x] }
    k8s_targets = []
    vm_targets = []

    if thing.is_a?(Stacks::CustomServices)
      k8s_targets = thing.k8s_machinesets.values
      vm_targets = vm_extraction.call(thing)
    elsif thing.is_a?(Stacks::MachineSet) && thing.kubernetes
      k8s_targets << thing
    else
      vm_targets = vm_extraction.call(thing)
    end

    [k8s_targets, vm_targets]
  end

  def vms_compile_output(targets)
    return nil if targets.empty?

    output = {}
    targets.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
      box_id = "#{stack.hostname}.mgmt.#{stack.domain}" # puppet refers to our hosts using the 'mgmt' name
      output[box_id] = {}
      output[box_id]["enc"] = stack.to_enc
      output[box_id]["spec"] = stack.to_spec
    end

    ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def k8s_compile_output(targets)
    return nil if targets.empty?

    output = {}
    targets.each do |machine_set|
      machine_set_id = "#{machine_set.children.first.fabric}-#{machine_set.environment.name}-#{machine_set.name}"
      output[machine_set_id] = machine_set.to_k8s(@app_deployer, @dns_resolver, @hiera_provider)
    end

    ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def deep_dup_to_avoid_yaml_aliases(output)
    ddup(output)
  end

  def ddup(object)
    case object
    when Hash
      object.inject({}) do |hash, (k, v)|
        hash[ddup(k)] = ddup(v)
        hash
      end
    when Array
      object.inject([]) { |a, e| a << ddup(e) }
    when NilClass, Numeric, TrueClass, FalseClass, Method
      object
    when Symbol
      object.to_s
    else
      object.dup
    end
  end

  def do_clean(thing, all = false)
    k8s_targets, vm_targets = split_k8s_from_vms(thing) do |x|
      if x.is_a?(Stacks::CustomServices)
        x.children
      else
        [x]
      end
    end

    k8s_targets.each do |t|
      clean_k8s(t)
    end

    vm_targets.each do |t|
      clean_vm(t, all)
    end
  end

  def clean_k8s(machineset)
    k8s_defns = machineset.to_k8s(@app_deployer, @dns_resolver, @hiera_provider)

    environment = machineset.environment.name
    machineset_name = machineset.name
    k8s_defns.each do |defn|
      resource_kind = defn['kind'].downcase

      stdout_str, error_str, status = Open3.capture3('kubectl',
                                                     'delete',
                                                     resource_kind,
                                                     '-l',
                                                     "stack=#{machineset.stack.name},machineset=#{machineset_name}",
                                                     '-n', environment)
      if status.success?
        logger(Logger::INFO) { stdout_str }
      else
        fail "Failed to delete k8s resource definitions - error: #{error_str}"
      end
    end
  end

  def clean_vm(thing, all = false)
    @nagios.nagios_schedule_downtime(thing)
    @cleaner.clean_nodes(thing)
    @puppet.puppet_clean(thing)
    @cleaner.clean_traces(thing) if all
  end

  def reprovision_vm(services, thing)
    clean_vm(thing)
    provision_vm(services, thing, false)
  end

  def apply_k8s(machineset, stack_name)
    k8s_defns = machineset.to_k8s(@app_deployer, @dns_resolver, @hiera_provider)
    k8s_defns_yaml = generate_k8s_defns_yaml(k8s_defns)

    apply_and_prune_k8s_defns(k8s_defns_yaml, stack_name, machineset.name)
  end

  def provision_vm(services, thing, initial = true)
    if initial
      # prepare dependencies
      @dns.do_allocate_vips(thing)
      @dns.do_allocate_ips(thing)
      @puppet.do_puppet_run_on_dependencies(thing)
    end

    @core_actions.get_action("launch").call(services, thing)
    sign_results = @puppet.puppet_wait_for_autosign(thing)

    # sometimes the one-time password auto-sign fails, and we do not know why
    unless sign_results.all_passed?
      failed_fqdns = sign_results.all.select { |_, res| res != "success" }.keys
      logger(Logger::WARN) { "puppet auto-sign failed for: #{failed_fqdns.join(', ')}" }
      logger(Logger::INFO) { "falling back to poll sign for these hosts" }
      poll_sign_success = @puppet.poll_sign(failed_fqdns, 30)
      fail "poll sign also failed" unless poll_sign_success
    end

    puppet_results = @puppet.puppet_wait_for_run_completion(thing)

    unless puppet_results.all_passed?
      logger(Logger::ERROR) { "One or more puppet runs have failed" }
      logger(Logger::INFO) { "Attempting to stop mcollective on hosts whose puppet runs failed" }
      require 'stackbuilder/support/mcollective_service'
      Support::MCollectiveService.new.stop_service("mcollective", puppet_results.failed + puppet_results.unaccounted_for)
      fail("Puppet runs have timed out or failed")
    end

    @app_deployer.deploy_applications(thing)
    @nagios.nagios_schedule_uptime(thing)

    @nagios.do_nagios_register_new(thing) if initial
  end

  def generate_k8s_defns_yaml(k8s_defns)
    k8s_defns.map do |k8s_defn|
      ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(k8s_defn))
    end.join("\n")
  end

  def apply_and_prune_k8s_defns(k8s_defns_yaml, stack_name, machine_set_name)
    command = ['kubectl', 'apply', '--prune', '-l', "stack=#{stack_name},machineset=#{machine_set_name}", '-f', '-']
    logger(Logger::DEBUG) { "running command: #{command.join(' ')}" }
    stdout_str, error_str, status = Open3.capture3(*command, :stdin_data => k8s_defns_yaml)
    if status.success?
      logger(Logger::INFO) { stdout_str }
    else
      fail "Failed to apply k8s resource definitions - error: #{error_str}"
    end
  end
end
