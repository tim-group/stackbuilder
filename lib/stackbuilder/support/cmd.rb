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
    @cmds = %w(audit compile ls lsenv enc clean provision reprovision)
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
        box_id = "#{stack.hostname}.#{stack.domain}"
        output[box_id] = {}
        output[box_id]["enc"] = stack.to_enc
        output[box_id]["spec"] = stack.to_spec
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
    else
      logger(Logger::FATAL) { "invalid command \"#{cmd}\"" }
      exit 1
    end
  end

  # XXX do this properly
  def clean(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{to_rake_stack_name(machine_def)}:clean")
  end

  # XXX do this properly
  def provision(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{to_rake_stack_name(machine_def)}:provision")
  end

  # XXX do this properly
  def reprovision(_argv)
    machine_def = check_and_get_stack
    system("cd #{$options[:path]} && env=#{$environment.name} rake sbx:#{to_rake_stack_name(machine_def)}:reprovision")
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

  # XXX won't be needed if system("...rake...") is no longer used in the commands above
  def to_rake_stack_name(machine_def)
    machine_def.respond_to?(:mgmt_fqdn) ? machine_def.mgmt_fqdn : machine_def.name
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
