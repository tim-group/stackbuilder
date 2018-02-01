require 'stackbuilder/support/zamls'
require 'stackbuilder/support/nagios'
require 'stackbuilder/support/cmd_audit'
require 'stackbuilder/support/cmd_ls'
require 'stackbuilder/support/cmd_nagios'
require 'stackbuilder/support/cmd_puppet'
require 'stackbuilder/support/cmd_clean'
require 'stackbuilder/support/cmd_provision'
require 'stackbuilder/support/cmd_orc'
require 'stackbuilder/stacks/core/actions'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
# long and complicated commands go to their own modules in their own files.
class CMD
  attr_reader :cmds # this list is just a safety check

  def initialize
    @cmds = %w(audit compile dependencies dependents diff dns sbdiff ls lsenv enc spec clean clean_all provision reprovision terminus test)
    @core_actions = Object.new
    @core_actions.extend(Stacks::Core::Actions)
  end

  include CMDAudit
  include CMDLs
  include CMDNagios
  include CMDPuppet
  include CMDClean
  include CMDProvision
  include CMDOrc

  # dump all the info from stackbuilder-config into one file, to enable manipulation with external tools.
  # use yaml, as that's what puppet reads in
  def compile(_argv)
    output = {}
    $factory.inventory.environments.sort.each do |_envname, env|
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        box_id = "#{stack.hostname}.mgmt.#{stack.domain}" # puppet refers to our hosts using the 'mgmt' name
        output[box_id] = {}
        output[box_id]["enc"] = stack.to_enc
        output[box_id]["spec"] = stack.to_spec
      end
    end
    puts ZAMLS.to_zamls(deep_dup_to_avoid_yaml_aliases(output))
  end

  def diff(_argv)
    diff_tool = ENV['DIFF'] || '/usr/bin/sdiff -s'
    sbc_path = ENV['STACKBUILDER_CONFIG_PATH'] || '.'

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
    $factory.inventory.environments.sort.each do |_envname, env|
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
      logger(Logger::FATAL) { "\"#{$options[:stack]}\" is not a machine fqdn" }
      exit 1
    end
  end

  def spec(_argv)
    machine_def = check_and_get_stack

    if machine_def.respond_to?(:to_spec)
      puts ZAMLS.to_zamls(machine_def.to_spec)
    else
      logger(Logger::FATAL) { "\"#{$options[:stack]}\" is not a machine fqdn" }
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
      system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:allocate_ips")
    when 'free_ips'
      system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:free_ips")
    when 'allocate_vips'
      system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:allocate_vips")
    when 'free_vips'
      system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:free_vips")
    else
      logger(Logger::FATAL) { "invalid sub command \"#{cmd}\"" }
      exit 1
    end
  end

  # XXX do this properly
  def provision(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:provision")
  end

  # XXX do this properly
  def test(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:test")
  end

  def reprovision(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def)
    do_provision_machine($factory.services, machine_def)
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

  private

  def ensure_is_machine(machine_def)
    if !machine_def.is_a?(Stacks::MachineDef)
      logger(Logger::FATAL) { "\"#{$options[:stack]}\" is not a machine fqdn" }
      exit 1
    end
    machine_def
  end

  def check_and_get_stack
    if $options[:stack].nil?
      logger(Logger::FATAL) { 'option "stack" not set' }
      exit 1
    end

    machine_def = $environment.find_stack($options[:stack])
    if machine_def.nil? then
      logger(Logger::FATAL) { "stack \"#{$options[:stack]}\" not found" }
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

# XXX ?
module Opt
  def self.stack
    logger(Logger::DEBUG) { ":primary_site for \"#{$environment.name}\" is \"#{$environment.options[:primary_site]}\"" }

    if $options[:stack].nil?
      logger(Logger::FATAL) { 'option "stack" not set' }
      exit 1
    end

    machine_def = $environment.find_stack($options[:stack])
    if machine_def.nil? then
      logger(Logger::FATAL) { "stack \"#{$options[:stack]}\" not found" }
      exit 1
    end

    machine_def
  end
end
