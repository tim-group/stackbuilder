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
    @cmds = %w(audit compile diff ls lsenv enc spec clean clean_all provision reprovision terminus test)
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

  def diff(argv)
    diff_type = arg.shift if argv.size > 0
    diff_tool = ENV['DIFF'] || '/usr/bin/sdiff -s'
    sbc_path = ENV['STACKBUILDER_CONFIG_PATH'] || '.'

    if diff_type == '-sb'
      system("sudo apt-get install stackbuilder && stacks compile > /tmp/before")
      system("rake package install  && stacks compile > /tmp/after")
    else
      system("cd #{sbc_path} && git checkout HEAD~1 && stacks compile > /tmp/before")
      system("cd #{sbc_path} && git checkout master && stacks compile > /tmp/after")
    end
    system("#{diff_tool} /tmp/before /tmp/after")
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
