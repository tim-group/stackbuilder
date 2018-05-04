require 'stackbuilder/support/zamls'
require 'stackbuilder/support/nagios'
require 'stackbuilder/stacks/core/actions'
require 'stackbuilder/support/subscription'
require 'stackbuilder/support/cmd_audit'
require 'stackbuilder/support/cmd_ls'
require 'stackbuilder/support/cmd_nagios'
require 'stackbuilder/support/cmd_puppet'
require 'stackbuilder/support/cmd_dns'
require 'stackbuilder/support/cmd_clean'
require 'stackbuilder/support/cmd_provision'
require 'stackbuilder/support/cmd_deploy'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
# long and complicated commands go to their own modules in their own files.
class CMD
  attr_reader :cmds # this list is just a safety check

  def initialize(factory, environment, stack = nil)
    @factory = factory
    @environment = environment
    @stack = stack
    @cmds = %w(audit compile dependencies dependents diff dns sbdiff ls lsenv enc spec clean clean_all launch provision reprovision terminus test showvnc)
    @core_actions = Object.new
    @core_actions.extend(Stacks::Core::Actions)
    @subscription = Subscription.new
    @subscription.start(["provision.*", "puppet_status"])
  end

  include CMDAudit
  include CMDLs
  include CMDNagios
  include CMDPuppet
  include CMDDns
  include CMDClean
  include CMDProvision
  include CMDDeploy

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
      do_allocate_ips(@factory.services, machine_def)
    when 'free_ips'
      do_free_ips(@factory.services, machine_def)
    when 'allocate_vips'
      do_allocate_vips(machine_def)
    when 'free_vips'
      do_free_vips(machine_def)
    else
      logger(Logger::FATAL) { "invalid sub command \"#{cmd}\"" }
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

  def launch(_argv)
    machine_def = check_and_get_stack
    do_launch(@factory.services, machine_def)
  end

  def provision(_argv)
    machine_def = check_and_get_stack

    # prepare dependencies
    do_allocate_vips(machine_def)
    do_allocate_ips(@factory.services, machine_def)
    do_puppet_run_on_dependencies(machine_def)

    do_provision_machine(@factory.services, machine_def)

    do_nagios_register_new(machine_def)
  end

  def reprovision(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def)
    do_provision_machine(@factory.services, machine_def)
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
end
