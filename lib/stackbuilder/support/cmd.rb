require 'stackbuilder/support/zamls'
require 'stackbuilder/support/cmd_audit'
require 'stackbuilder/support/cmd_find_rogue'
require 'stackbuilder/support/cmd_ls'
require 'stackbuilder/support/cmd_orc'
require 'stackbuilder/support/cmd_nagios'

# all public methods in this class are valid stacks commands.
# the only argument is argv, i.e. the remaining cli arguments not recognized by getoptlong.
# long and complicated commands go to their own modules in their own files.
class CMD
  attr_reader :cmds # this list is just a safety check
  def initialize
    @cmds = %w(audit find_rogue ls orc nagios dump_enc dump_spec enc puppet nagios)
  end
  include CMDAudit
  include CMDFindRogue
  include CMDLs
  include CMDOrc
  include CMDNagios

  def dump_enc(_argv)
    $factory.inventory.environments.sort.each do |envname, env|
      next if envname == 'lon' # XXX 15.07.15 mmazurek/scarytom: special case 'lon' until it's fixed
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        puts "running to_enc on #{stack.hostname}.#{stack.domain}/#{envname}:"
        puts ZAMLS.to_zamls(stack.to_enc)
      end
    end
  end

  def dump_spec(_argv)
    $factory.inventory.environments.sort.each do |envname, env|
      next if envname == 'lon' # XXX 15.07.15 mmazurek/scarytom: special case 'lon' until it's fixed
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        puts "running to_spec on #{stack.hostname}.#{stack.domain}/#{envname}:"
        puts ZAMLS.to_zamls(stack.to_spec)
      end
    end
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

  def puppet(argv)
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
