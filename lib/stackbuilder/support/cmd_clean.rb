module CMDClean
  def clean_traces(machine_def)
    hosts = []
    machine_def.accept do |child_machine_def|
      hosts << child_machine_def.mgmt_fqdn if child_machine_def.respond_to?(:mgmt_fqdn)
    end

    require 'stackbuilder/support/mcollective_hostcleanup'
    mcollective_hostcleanup = Support::MCollectiveHostcleanup.new
    %w(nagios mongodb puppet).each do |action|
      hosts.each { |fqdn| mcollective_hostcleanup.hostcleanup(fqdn, action) }
    end
  end

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
end
