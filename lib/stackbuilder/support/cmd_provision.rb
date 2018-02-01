module CMDProvision
  def launch(_argv)
    machine_def = check_and_get_stack
    do_launch($factory.services, machine_def)
  end

  def do_launch(services, machine_def)
    @core_actions.get_action("launch").call(services, machine_def)
  end

  def do_allocate(services, machine_def)
    @core_actions.get_action("allocate").call(services, machine_def)
  end

  def do_allocate_ips(services, machine_def)
    @core_actions.get_action("allocate_ips").call(services, machine_def)
  end
end
