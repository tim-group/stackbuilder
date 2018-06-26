require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_hostcleanup'

class Support::Cleaner
  def initialize(compute_controller)
    @compute_controller = compute_controller
    @mco_hc = Support::MCollectiveHostcleanup.new
  end

  def clean_traces(machine_def)
    hosts = []
    machine_def.accept do |child_machine_def|
      hosts << child_machine_def.mgmt_fqdn if child_machine_def.respond_to?(:mgmt_fqdn)
    end

    %w(nagios mongodb puppet).each do |action|
      hosts.each { |fqdn| @mco_hc.hostcleanup(fqdn, action) }
    end
  end

  def clean_nodes(machine_def)
    @compute_controller.clean(machine_def.to_specs) do
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
