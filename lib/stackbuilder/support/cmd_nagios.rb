module CMDNagios
  def nagios(argv)
    cmd = argv.shift
    if cmd.nil? then
      logger(Logger::FATAL) { 'nagios needs a subcommand' }
      exit 1
    end

    machine_def = check_and_get_stack

    case cmd
    when 'disable'
      nagios_schedule_downtime(machine_def)
    when 'enable'
      nagios_cancel_downtime(machine_def)
    else
      logger(Logger::FATAL) { "invalid command \"#{cmd}\"" }
      exit 1
    end
  end

  def do_nagios_register_new(machine_def)
    hosts = hosts_for(machine_def)
    nagios_helper = Support::Nagios::Service.new
    nagios_helper.register_new_machines(hosts)
  end

  private

  def nagios_schedule_downtime(machine_def)
    hosts = hosts_for(machine_def)

    nagios_helper = Support::Nagios::Service.new
    downtime_secs = 1800 # 1800 = 30 mins
    nagios_helper.schedule_downtime(hosts, downtime_secs) do
      on :success do |response_hash|
        logger(Logger::INFO) do
          "successfully scheduled #{downtime_secs} seconds downtime for #{response_hash[:machine]} " \
          "result: #{response_hash[:result]}"
        end
      end
      on :failed do |response_hash|
        logger(Logger::INFO) do
          "failed to schedule #{downtime_secs} seconds downtime for #{response_hash[:machine]} " \
          "result: #{response_hash[:result]}"
        end
      end
    end
  end

  def nagios_cancel_downtime(machine_def)
    hosts = hosts_for(machine_def)

    nagios_helper = Support::Nagios::Service.new
    nagios_helper.cancel_downtime(hosts) do
      on :success do |response_hash|
        logger(Logger::INFO) do
          "successfully cancelled downtime for #{response_hash[:machine]} " \
          "result: #{response_hash[:result]}"
        end
      end
      on :failed do |response_hash|
        logger(Logger::INFO) do
          "failed to cancel downtime for #{response_hash[:machine]} " \
          "result: #{response_hash[:result]}"
        end
      end
    end
  end

  def hosts_for(machine_def)
    hosts = []
    machine_def.accept do |child_machine_def|
      hosts << child_machine_def if child_machine_def.respond_to?(:mgmt_fqdn)
    end
    hosts
  end
end
