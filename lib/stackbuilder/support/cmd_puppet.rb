module CMDPuppet
  require 'stackbuilder/support/cmd'

  def self.puppet(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'puppet needs a subcommand' }
      exit 1
    end

    machine_def = CMD.get_stack

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
end
