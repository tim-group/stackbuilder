require 'stackbuilder/support/zamls'
require 'stackbuilder/support/nagios'
require 'stackbuilder/stacks/core/actions'
require 'stackbuilder/support/subscription'
require 'stackbuilder/support/audit_site'
require 'stackbuilder/support/audit_vms'
require 'stackbuilder/support/env_listing'
require 'stackbuilder/support/puppet'
require 'stackbuilder/support/dns'
require 'stackbuilder/support/cleaner'
require 'stackbuilder/support/live_migration'
require 'stackbuilder/support/host_builder'
require 'stackbuilder/support/app_deployer'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
class CMD
  attr_reader :cmds # this list is just a safety check
  attr_reader :read_cmds # this list is just a safety check
  attr_reader :write_cmds # this list is just a safety check

  def initialize(factory, environment, stack = nil)
    @factory = factory
    @environment = environment
    @stack = stack
    @read_cmds = %w(audit audit_vms compile dependencies dependents diff sbdiff ls lsenv enc spec terminus test showvnc check_definition)
    @write_cmds = %w(dns clean clean_all launch allocate provision reprovision move clear_host rebuild_host build_new_host)
    @cmds = @read_cmds + @write_cmds
    @core_actions = Object.new
    @core_actions.extend(Stacks::Core::Actions)
    @dns = Support::Dns.new(@factory, @core_actions)
    @nagios = Support::Nagios.new

    subscription = Subscription.new
    subscription.start(["provision.*", "puppet_status"])
    @puppet = Support::Puppet.new(subscription)
  end

  # dump all the info from stackbuilder-config into one file, to enable manipulation with external tools.
  # use yaml, as that's what puppet reads in
  def compile(_argv)
    targets = []

    if @stack.nil?
      @factory.inventory.environments.sort.each do |_envname, env|
        targets += env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }
      end
    else
      targets = check_and_get_stack.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }
    end

    output = {}
    targets.each do |stack|
      box_id = "#{stack.hostname}.mgmt.#{stack.domain}" # puppet refers to our hosts using the 'mgmt' name
      output[box_id] = {}
      output[box_id]["enc"] = stack.to_enc
      output[box_id]["spec"] = stack.to_spec
    end

    puts ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def diff(_argv)
    diff_tool = ENV['DIFF'] || '/usr/bin/sdiff -s'
    sbc_path = @factory.path

    require 'tempfile'
    before_file = Tempfile.new('before')
    after_file = Tempfile.new('after')

    system("cd #{sbc_path} && git checkout HEAD~1 && stacks compile > #{before_file.path}")
    system("cd #{sbc_path} && git checkout master && stacks compile > #{after_file.path}") if $CHILD_STATUS.to_i == 0
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
      logger(Logger::FATAL) { "\"#{@stack}\" is not a machine fqdn" }
      exit 1
    end
  end

  def spec(_argv)
    machine_def = check_and_get_stack

    if machine_def.respond_to?(:to_spec)
      puts ZAMLS.to_zamls(machine_def.to_spec)
    else
      logger(Logger::FATAL) { "\"#{@stack}\" is not a machine fqdn" }
      exit 1
    end
  end

  def dns(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'dns needs a subcommand' }
      exit 1
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
      exit 1
    end
  end

  def nagios(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'nagios needs a subcommand' }
      exit 1
    end

    machine_def = check_and_get_stack

    case cmd
    when 'disable'
      @nagios.nagios_schedule_downtime(machine_def)
    when 'enable'
      @nagios.nagios_cancel_downtime(machine_def)
    else
      logger(Logger::FATAL) { "invalid command \"#{cmd}\"" }
      exit 1
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
      exit 1
    end
    result
  end

  def ls(_argv)
    Support::EnvListing.new($options[:terse]).ls(@stack ? check_and_get_stack : @environment)
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
      auditor.audit_site_vms(site)
    else
      host_fqdn = argv[0]
      auditor.audit_host_vms(host_fqdn)
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
    machine_def = check_and_get_stack

    # prepare dependencies
    @dns.do_allocate_vips(machine_def)
    @dns.do_allocate_ips(machine_def)
    @puppet.do_puppet_run_on_dependencies(machine_def)

    do_provision_machine(@factory.services, machine_def)
    @nagios.do_nagios_register_new(machine_def)
  end

  def reprovision(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def)
    do_provision_machine(@factory.services, machine_def)
  end

  def move(_argv)
    machines = check_and_get_stack.flatten

    if machines.size != 1
      logger(Logger::FATAL) { "moving more than one machine not supported" }
      exit 1
    end

    machine = machines.first
    hosts = @factory.host_repository.find_compute_nodes(machine.fabric, false, false, false)
    host = hosts.find { |h| h.allocated_machines.map { |m| m[:hostname] }.include?(machine.hostname) }

    if host.nil?
      logger(Logger::FATAL) { "#{machine.hostname} is not provisioned" }
      exit 1
    end

    Support::LiveMigrator.new(@factory, host).move(machine)
  end

  def clear_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to clear" }
      exit 1
    end

    host_fqdn = argv[0]
    host = @factory.host_repository.find_compute_node(host_fqdn, false, false, false)

    if host.nil?
      logger(Logger::FATAL) { "unable to find #{host_fqdn}" }
      exit 1
    end

    Support::LiveMigrator.new(@factory, host).move_all
  end

  def rebuild_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to rebuild" }
      exit 1
    end

    Support::HostBuilder.new(@factory, @nagios, @puppet).rebuild(argv[0])
  end

  def build_new_host(argv)
    if argv.size != 1
      logger(Logger::FATAL) { "You must specify a host to rebuild" }
      exit 1
    end

    Support::HostBuilder.new(@factory, @nagios, @puppet).build_new(argv[0])
  end

  def dependencies(_argv)
    machine_def = ensure_is_machine(check_and_get_stack)

    service_dependencies = machine_def.virtual_service.virtual_services_that_i_depend_on
    dependencies = service_dependencies.map { |machine_set| machine_set.children.map(&:identity) }.flatten
    puts ZAMLS.to_zamls(dependencies)
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

  def ensure_is_machine(machine_def)
    if !machine_def.is_a?(Stacks::MachineDef)
      logger(Logger::FATAL) { "\"#{@stack}\" is not a machine fqdn" }
      exit 1
    end
    machine_def
  end

  def check_and_get_stack
    if @stack.nil?
      logger(Logger::FATAL) { 'option "stack" not set' }
      exit 1
    end

    machine_def = @environment.find_stack(@stack)
    if machine_def.nil? then
      logger(Logger::FATAL) { "stack \"#{@stack}\" not found" }
      exit 1
    end

    machine_def
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

  def do_clean(machine_def, all = false)
    cleaner = Support::Cleaner.new(@factory.compute_controller)
    @nagios.nagios_schedule_downtime(machine_def)
    cleaner.clean_nodes(machine_def)
    @puppet.puppet_clean(machine_def)
    cleaner.clean_traces(machine_def) if all
  end

  def do_provision_machine(services, machine_def)
    @core_actions.get_action("launch").call(services, machine_def)
    sign_results = @puppet.puppet_wait_for_autosign(machine_def)

    # sometimes the one-time password auto-sign fails, and we do not know why
    unless sign_results.all_passed?
      failed_fqdns = sign_results.all.select { |_, res| res != "success" }.keys
      logger(Logger::WARN) { "puppet auto-sign failed for: #{failed_fqdns.join(', ')}" }
      logger(Logger::INFO) { "falling back to poll sign for these hosts" }
      poll_sign_success = @puppet.poll_sign(failed_fqdns, 30)
      fail "poll sign also failed" unless poll_sign_success
    end

    puppet_results = @puppet.puppet_wait_for_run_completion(machine_def)

    unless puppet_results.all_passed?
      logger(Logger::ERROR) { "One or more puppet runs have failed" }
      logger(Logger::INFO) { "Attempting to stop mcollective on hosts whose puppet runs failed" }
      require 'stackbuilder/support/mcollective_service'
      Support::MCollectiveService.new.stop_service("mcollective", puppet_results.failed + puppet_results.unaccounted_for)
      fail("Puppet runs have timed out or failed")
    end

    Support::AppDeployer.new.deploy_applications(machine_def)
    @nagios.nagios_cancel_downtime(machine_def)
  end
end
