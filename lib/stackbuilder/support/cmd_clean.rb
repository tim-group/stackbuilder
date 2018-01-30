require 'stackbuilder/support/mcollective_puppet'

module CMDClean
  def clean(_argv)
    machine_def = check_and_get_stack
    do_clean(machine_def)
  end

  def do_clean(machine_def)
    # Note that the ordering here is important - must have killed VMs before
    # removing their puppet cert, otherwise we have a race condition
    nagios_schedule_downtime(machine_def)
    clean_nodes(machine_def)
    puppet_clean(machine_def)
  end

  private

  def clean_nodes(machine_def)
    computecontroller = Compute::Controller.new
    computecontroller.clean(machine_def.to_specs) do
      on :success do |vm, msg|
        logger(Logger::INFO) { "successfully cleaned #{vm}: #{msg}" }
      end
      on :failure do |vm, msg|
        logger(Logger::ERROR) { "failed to clean #{vm}: #{msg}" }
      end
      on :unaccounted do |vm|
        logger(Logger::WARN) { "VM was unaccounted for: #{vm}" }
      end
    end
  end

  include Support::MCollectivePuppet

  def puppet_clean(machine_def)
    puppet_certs_to_clean = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        if child_machine_def.needs_signing?
          puppet_certs_to_clean << child_machine_def.mgmt_fqdn
        else
          logger(Logger::INFO) { "removal of cert not needed for #{child_machine_def.mgmt_fqdn}" }
        end
      end
    end

    ca_clean(puppet_certs_to_clean) do
      on :success do |machine|
        logger(Logger::INFO) { "successfully removed cert for #{machine}" }
      end
      on :failed do |machine|
        logger(Logger::WARN) { "failed to remove cert for #{machine}" }
      end
    end
  end
end
