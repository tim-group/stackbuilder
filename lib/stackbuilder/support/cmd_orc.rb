$LOAD_PATH << '/usr/local/lib/site_ruby/timgroup'
require 'orc/util/factory' # XXX decouple orc from stackbuiler somehow
$LOAD_PATH.delete('/usr/local/lib/site_ruby/timgroup')

module CMDOrc
  def orc_resolve(_argv)
    machine_def = check_and_get_stack
    do_orc_resolve(machine_def)
  end

  def do_orc_resolve(machine_def)
    valid = false

    if machine_def.is_a? Stacks::Services::AppServer
      valid = true
      do_resolve(machine_def.virtual_service.application, machine_def.environment.name)
    else
      applications = Set.new
      machine_def.accept do |child_machine_def|
        next unless child_machine_def.is_a? Stacks::Services::AppServer
        valid = true
        applications << child_machine_def.virtual_service.application
      end
      applications.to_a.each do |app|
        do_resolve(app, machine_def.environment.name)
      end
    end

    # false positive
    # rubocop:disable Style/GuardClause
    if !valid
      logger(Logger::INFO) { "machine_def \"#{machine_def.name}\" cannot be orc-resolved" }
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
