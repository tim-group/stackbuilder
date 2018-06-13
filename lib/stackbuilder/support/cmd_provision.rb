module CMDProvision
  def do_provision_machine(services, machine_def)
    do_launch(services, machine_def)
    puppet_sign(machine_def)
    puppet_poll_sign(machine_def)

    puppet_results = puppet_wait(machine_def)

    unless puppet_results.all_passed?
      logger(Logger::INFO) { "Attempting to stop mcollective on hosts whose puppet runs failed" }
      stop_mcollective(puppet_results.failed + puppet_results.unaccounted_for)
      fail("Puppet runs have timed out or failed")
    end

    require 'stackbuilder/support/app_deployer'
    Support::AppDeployer.new.deploy_applications(machine_def)
  end

  def do_launch(services, machine_def)
    @core_actions.get_action("launch").call(services, machine_def)
  end

  def do_allocate(services, machine_def)
    @core_actions.get_action("allocate").call(services, machine_def)
  end

  private

  def stop_mcollective(fqdns)
    mco_client("service", :timeout => 5, :nodes => fqdns) do |mco|
      mco.stop(:service => "mcollective")
    end
  end
end
