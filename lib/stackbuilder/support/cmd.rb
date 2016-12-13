require 'stackbuilder/support/zamls'
require 'stackbuilder/support/cmd_audit'
require 'stackbuilder/support/cmd_ls'
require 'stackbuilder/support/cmd_orc'
require 'stackbuilder/support/cmd_nagios'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
# long and complicated commands go to their own modules in their own files.
class CMD
  attr_reader :cmds # this list is just a safety check
  def initialize
    @cmds = %w(audit compile dependables dependencies ls lsenv enc spec clean clean_all provision reprovision terminus test)
  end
  include CMDAudit
  include CMDLs
  include CMDOrc # XXX work in progress
  include CMDNagios # XXX work in progress

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

  # XXX work in progress
  def puppet(argv)
    logger(Logger::FATAL) { "work in progress" }
    exit 1

    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'puppet needs a subcommand' }
      exit 1
    end

    machine_def = check_and_get_stack

    logger(Logger::DEBUG) { "about to run puppet \"#{cmd}\" on \"#{machine_def.name}\"" }

    require 'stackbuilder/support/puppet'
    pctl = PuppetCtl.new

    case cmd
    when 'sign'
      pctl.sign(machine_def)
    when 'poll_sign'
      pctl.poll_sign(machine_def)
    when 'wait'
      pctl.wait(machine_def)
    when 'run'
      pctl.run(machine_def)
    when 'clean'
      pctl.clean(machine_def)
    when 'clean_all'
      pctl.clean_all(machine_def)
    else
      logger(Logger::FATAL) { "invalid command \"#{cmd}\"" }
      exit 1
    end
  end

  # XXX do this properly
  def clean(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:clean")
  end

  # XXX do this properly
  def clean_all(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]}" \
           " && env=#{$environment.name} rake sbx:#{machine_def.identity}:clean" \
           " && env=#{$environment.name} rake sbx:#{machine_def.identity}:clean_traces")
  end

  def dependables(_argv)
    node = check_and_get_stack
    puts ZAMLS.to_zamls(node.dependables_to_hash)
  end

  def dependencies(_argv)
    node = check_and_get_stack
    if node.kind_of? Stacks::MachineDef
      puts "Dependencies of machine #{node.mgmt_fqdn}:"
      puts ZAMLS.to_zamls(node.dependencies_to_hash)
      if node.respond_to? :virtual_service and not node.virtual_service.nil?
        puts "Inherited dependencies of associated machine_set:"
        puts ZAMLS.to_zamls(node.virtual_service.dependencies_to_hash)
      end
    elsif node.kind_of? Stacks::MachineSet
      puts "Dependencies of machine_set '#{node.name}':"
      puts ZAMLS.to_zamls(node.dependencies_to_hash)
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

  # XXX do this properly
  def reprovision(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{machine_def.identity}:reprovision")
  end

  private

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

# XXX
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
