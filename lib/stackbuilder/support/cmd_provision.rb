module CMDProvision
  def do_provision_machine(services, machine_def)
    do_launch(services, machine_def)
    puppet_sign(machine_def)
    puppet_poll_sign(machine_def)
    puppet_wait(machine_def)
    do_deploy_applications(machine_def)
    nagios_cancel_downtime(machine_def)
  end

  def do_launch(services, machine_def)
    @core_actions.get_action("launch").call(services, machine_def)
  end

  def do_allocate(services, machine_def)
    @core_actions.get_action("allocate").call(services, machine_def)
  end
end
