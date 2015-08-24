$LOAD_PATH << '/usr/local/lib/site_ruby/timgroup'
require 'orc/util/option_parser' # XXX decouple orc from stackbuiler somehow
$LOAD_PATH.delete('/usr/local/lib/site_ruby/timgroup')

module CMDOrc
  def resolve(_argv)
    machine_def = check_and_get_stack
    valid = false

    if machine_def.is_a? Stacks::Services::AppServer
      valid = true
      do_resolve(machine_def.virtual_service.application, machine_def.environment.name)
    else
      machine_def.accept do |child_machine_def|
        next unless child_machine_def.is_a? Stacks::Services::AppServer
        valid = true
        do_resolve(child_machine_def.virtual_service.application, machine_def.environment.name)
      end
    end

    # false positive
    # rubocop:disable Style/GuardClause
    if !valid
      logger(Logger::ERROR) { "machine_def \"#{machine_def.name}\" cannot be orc-resolved" }
      exit 1
    end
    # rubocop:enable Style/GuardClause
  end

  private

  def do_resolve(app, envname)
    factory = Orc::Factory.new(
      :application => app,
      :environment => envname
    )
    factory.cmdb_git.update
    factory.engine.resolve
  end
end
