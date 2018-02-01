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

  def clean_all(_argv)
    machine_def = check_and_get_stack
    do_clean_all(machine_def)
  end

  def do_clean_all(machine_def)
    do_clean(machine_def)
    do_clean_traces(machine_def)
  end

  def do_clean_traces(machine_def)
    hosts = []
    machine_def.accept do |child_machine_def|
      hosts << child_machine_def.mgmt_fqdn if child_machine_def.respond_to?(:mgmt_fqdn)
    end
    %w(nagios mongodb puppet).each do |action|
      hosts.each { |fqdn| hostcleanup(fqdn, action) }
    end
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

  # FIXME: Stolen from hostcleanup application, this does not belong here
  def status_code(status)
    return 'OK' if status
    'ERROR'
  end

  # FIXME: Stolen from hostcleanup application, this does not belong here
  def output_result(responses)
    responses.each do |resp|
      if resp.results[:statuscode] == 0
        printf(" %-48s: %s - %s, output: %s\n", resp.results[:sender], \
               resp.action, \
               status_code(resp.results[:data][:statuscode]), \
               resp.results[:data][:status])
      else
        printf(" %-48s: %s - ERROR %s\n", resp.results[:sender], resp.action, resp.results[:statusmsg])
      end
    end
  end

  # FIXME: Stolen from hostcleanup application, this does not belong here
  def hostcleanup(fqdn, action)
    mco_client('hostcleanup') do |hostcleanup_mc|
      hostcleanup_mc.progress = false
      hostcleanup_mc.reset_filter
      case action
      when 'puppet'
        hostcleanup_mc.class_filter('role::puppetserver')
        hostcleanup_mc.fact_filter 'logicalenv', '/(oy|pg|lon|st)/'
      when 'mongodb'
        hostcleanup_mc.class_filter('role::mcollective_registrationdb')
        hostcleanup_mc.fact_filter 'logicalenv', '/(oy|pg|lon|st)/'
      when 'nagios'
        hostcleanup_mc.class_filter('nagios')
        hostcleanup_mc.fact_filter 'domain', '/(oy|pg|lon)/'
      when 'metrics'
        hostcleanup_mc.class_filter('metrics')
      end
      output_result hostcleanup_mc.send(action, :fqdn => fqdn)
    end
  end
end
