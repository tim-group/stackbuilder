require 'stackbuilder/support/zamls'
require 'stackbuilder/support/audit_site'
require 'stackbuilder/support/audit_vms'
require 'stackbuilder/support/env_listing'
require 'stackbuilder/support/live_migration'
require 'stackbuilder/support/host_builder'
require 'stackbuilder/support/dns_resolver'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/kubernetes_vm_model'
require 'stackbuilder/support/kubernetes_vm_prometheus_targets'
require 'stackbuilder/support/dependent_apps'
require 'open3'

# public methods in this class (and whose name is included in the :cmds instance variable) are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
class CMD
  attr_reader :cmds # this list is just a safety check
  attr_reader :read_cmds # this list is just a safety check
  attr_reader :write_cmds # this list is just a safety check

  # rubocop:disable Metrics/ParameterLists
  def initialize(factory, core_actions, dns, nagios, subscription, puppet, app_deployer, dns_resolver,
                 hiera_provider, cleaner, environment, stack_name = nil, stash = false, validate = true)
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
    @validate = validate
    @read_cmds = %w(audit audit_vms compile
                    dependencies dependents diff
                    sbdiff ls lsenv enc spec
                    terminus test showvnc
                    check_definition kubernetes_vm_recording_rules
                    kubernetes_vm_prometheus_targets)
    @write_cmds = %w(dns clean clean_all
                     launch allocate provision
                     reprovision apply move clear_host
                     rebuild_host build_new_host
                     unsafely_start_dependent_apps unsafely_stop_dependent_apps)
    @cmds = @read_cmds + @write_cmds
  end
  # rubocop:enable Metrics/ParameterLists

  #############################################################################
  # Commands that operate on a specific thing:
  #   * stack
  #   * machineset
  #   * machinedef
  #   * vm fqdn
  #   * environment
  #############################################################################

  # dump all the info from stackbuilder-config into one file, to enable manipulation with external tools.
  # use yaml, as that's what puppet reads in
  def compile(_argv)
    puts generate_compile_output
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

  def dependencies(_argv)
    machine_set = convert_to_machine_set(check_and_get_stack(true))

    puts ZAMLS.to_zamls(machine_set.virtual_services_that_i_depend_on.map do |s|
      if s.kubernetes
        s
      else
        s.children
      end
    end.flatten.map(&:identity))
  end

  def dependents(_argv)
    machine_set = convert_to_machine_set(check_and_get_stack(true))

    puts ZAMLS.to_zamls(machine_set.virtual_services_that_depend_on_me.map do |s|
      if s.kubernetes
        s
      else
        s.children
      end
    end.flatten.map(&:identity))
  end

  def unsafely_stop_dependent_apps(_argv)
    machine_set = convert_to_machine_set(check_and_get_stack(true))
    dry_run_only = $options[:dry_run]
    dependent_apps = Support::DependentApps.new(@environment, machine_set)

    dependent_apps.unsafely_stop_commands.each do |dependent_app_command|
      if dry_run_only
        puts "Would stop dependent kubernetes using: `#{dependent_app_command.describe}`"
      else
        system(dependent_app_command.executable)
      end
    end
  end

  def unsafely_start_dependent_apps(_argv)
    machine_set = convert_to_machine_set(check_and_get_stack(true))
    dry_run_only = $options[:dry_run]
    dependent_apps = Support::DependentApps.new(@environment, machine_set)

    dependent_apps.unsafely_start_commands.each do |dependent_app_command|
      if dry_run_only
        puts "Would start dependent kubernetes using: `#{dependent_app_command.describe}`"
      else
        case dependent_app_command
        when DependentAppMcoCommand
          system(dependent_app_command.executable)
        when DependentAppStacksApplyCommand
          apply_k8s(dependent_app_command.machine_set)
        end
      end
    end
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
          host_specs.each { |spec| puts "[0;31m#{spec[:hostname]} ==> failed (not provisioned)[0m" }
        else
          results = @factory.compute_node_client.check_vm_definitions(host_fqdn, host_specs)
          results.each do |host_result|
            sender = host_result[0]
            host_result[1].each do |vm_name, vm_result|
              colour = vm_result[0] == 'success' ? "[0;32m" : "[0;31m"
              puts "#{colour}#{vm_name} ==> #{vm_result[0]} (on host #{sender})[0m"
              puts "  #{vm_result[1].gsub("\n", "  \n")}" unless vm_result[0] == 'success'
            end
          end
        end
      end
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
    machine_def = check_and_get_stack(true)
    do_clean(machine_def)
    0
  end

  def clean_all(_argv)
    machine_def = check_and_get_stack(true)
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

  def provision(_argv)
    thing = check_and_get_stack(true)
    k8s_targets, vm_targets = split_k8s_from_vms(thing) do |x|
      if x.is_a?(Stacks::CustomServices)
        x.children
      else
        [x]
      end
    end

    ($options[:dependencies] ? expand_dependencies(k8s_targets) : k8s_targets).each do |t|
      @dns.do_allocate_vips(t)
      @puppet.do_puppet_run_on_dependencies(t) if $options[:dependencies]

      apply_k8s(t)
    end

    vm_targets.each do |t|
      provision_vm(@factory.services, t, true, $options[:dependencies])
    end
  end

  def reprovision(_argv)
    thing = check_and_get_stack(true)

    k8s_targets, vm_targets = split_k8s_from_vms(thing) do |x|
      if x.is_a?(Stacks::CustomServices)
        x.children
      else
        [x]
      end
    end

    unless $options[:update_version].nil?
      require 'orc/factory'
      vm_targets.each do |_t|
        fail '--update-version for VMs has not yet been implemented'
      end

      k8s_targets.each do |t|
        orc_factory = Orc::Factory.new(
          :application => t.application,
          :environment => t.environment.name,
          :group => 'blue'
        )
        orc_factory.high_level_orchestration.install($options[:update_version])
      end
    end

    ($options[:dependencies] ? expand_dependencies(k8s_targets) : k8s_targets).each do |t|
      apply_k8s(t)
    end

    vm_targets.each do |t|
      reprovision_vm(@factory.services, t, $options[:dependencies])
    end

    0
  end
  alias_method :apply, :reprovision

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

  #############################################################################
  # Commands that only operate on a specific environment and/or KVM host
  #############################################################################

  def lsenv(_argv)
    Support::EnvListing.new($options[:terse]).ls(@environment.environments.values, true)
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

  # express the model as prometheus metrics
  def kubernetes_vm_recording_rules(_argv)
    vm_model = Support::KubernetesVmModel.new(100)
    crds = vm_model.generate(@factory.inventory.environments.map(&:last), @environment.options[:primary_site])
    crds.each do |crd|
      puts YAML.dump(crd)
    end
  end

  # generate list of prometheus targets from the model
  def kubernetes_vm_prometheus_targets(_argv)
    vm_prometheus_targets = Support::KubernetesVmPrometheusTargets.new(@dns_resolver)
    crds = vm_prometheus_targets.generate(@factory.inventory.environments.map(&:last), @environment.options[:primary_site])
    crds.each do |crd|
      puts YAML.dump(crd)
    end
  end

  #############################################################################
  # Commands that operate on the whole inventory at once
  #############################################################################

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
        @factory.refresh(@validate)
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
      thing = check_and_get_stack(true)
      k8s_targets, vm_targets = split_k8s_from_vms(thing) { |x| x.flatten }
    end

    [vms_compile_output(vm_targets), k8s_compile_output(k8s_targets)].compact.join("\n")
  end

  def convert_to_machine_set(thing)
    if thing.is_a?(Stacks::MachineDef)
      thing.virtual_service
    elsif thing.is_a?(Stacks::MachineSet)
      thing
    else
      logger(Logger::FATAL) { "\"#{@stack_name}\" is not a machine fqdn or service name" }
      fail "Machine not found"
    end
  end

  def check_and_get_stack(accept_k8s = false)
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

    fail_on_k8s_if_command_not_supported(stacks.first, accept_k8s)

    stacks.first
  end

  def fail_on_k8s_if_command_not_supported(stack, accept_k8s)
    stack_contains_k8s_things = (stack.is_a?(Stacks::CustomServices) && !stack.k8s_machinesets.empty?) ||
                                (stack.is_a?(Stacks::MachineSet) && stack.kubernetes)

    fail "The specified command cannot be used on stacks and/or services containing kubernetes definitions" if !accept_k8s && stack_contains_k8s_things
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
      begin
        output[box_id] = {}
        output[box_id]["enc"] = stack.to_enc
        output[box_id]["spec"] = stack.to_spec
      rescue StandardError => e
        raise "Error producing ENC/Spec for #{box_id}: #{e.message}"
      end
    end

    ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def k8s_compile_output(targets)
    return nil if targets.empty?

    output = {}
    targets.each do |machine_set|
      begin
        bundles = machine_set.to_k8s(@app_deployer, @dns_resolver, @hiera_provider)
        bundles.each do |bundle|
          machine_set_id = "#{bundle.site}-#{bundle.environment_name}-#{bundle.machine_set_name}"
          output[machine_set_id] = bundle.resources
        end
      rescue StandardError => e
        raise "Error producing resource bundle for #{machine_set.name} in #{machine_set.environment.name}: #{e.message}"
      end
    end

    ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def expand_dependencies(machine_sets)
    (machine_sets.flat_map { |t| t.virtual_services_that_i_depend_on.select(&:kubernetes) } + machine_sets).uniq
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
    machineset.to_k8s(@app_deployer, @dns_resolver, @hiera_provider).each(&:clean)
  end

  def clean_vm(thing, all = false)
    @nagios.nagios_schedule_downtime(thing)
    @cleaner.clean_nodes(thing)
    @puppet.puppet_clean(thing)
    @cleaner.clean_traces(thing) if all
  end

  def reprovision_vm(services, thing, run_on_dependencies)
    clean_vm(thing)
    provision_vm(services, thing, false, run_on_dependencies)
  end

  def apply_k8s(machineset)
    bundles = machineset.to_k8s(@app_deployer, @dns_resolver, @hiera_provider)
    self.class.include Support::MCollective
    bundles.each do |bundle|
      mco_client('k8ssecret', :fabric => bundle.site) do |client|
        logger(Logger::INFO) { "Applying #{bundle.site} #{bundle.environment_name} #{bundle.machine_set_name}" }
        bundle.apply_and_prune(client)
      end
    end
  end

  def provision_vm(services, thing, initial, run_on_dependencies)
    if initial
      # prepare dependencies
      @dns.do_allocate_vips(thing)
      @dns.do_allocate_ips(thing)
      @puppet.do_puppet_run_on_dependencies(thing) if run_on_dependencies
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
end
