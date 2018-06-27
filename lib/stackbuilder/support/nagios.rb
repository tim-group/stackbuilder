require 'stackbuilder/support/namespace'
require 'stackbuilder/support/callback'
require 'stackbuilder/support/mcollective_nagsrv'

class Support::Nagios
  def do_nagios_register_new(machine_def)
    hosts = hosts_for(machine_def)
    nagios_helper = Support::NagiosService.new
    nagios_helper.register_new_machines(hosts)
  end

  def nagios_schedule_downtime(machine_def)
    hosts = hosts_for(machine_def)

    nagios_helper = Support::NagiosService.new
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

    nagios_helper = Support::NagiosService.new
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

  private

  def hosts_for(machine_def)
    hosts = []
    machine_def.accept do |child_machine_def|
      hosts << child_machine_def if child_machine_def.respond_to?(:mgmt_fqdn)
    end
    hosts
  end
end

class Support::NagiosService
  def initialize(options = {})
    @service = options[:service] || Support::MCollectiveNagsrv.new
  end

  def schedule_downtime(machines, duration = 600, &block)
    callback = Support::Callback.new(&block)
    machines.each do |machine|
      response = @service.schedule_downtime(machine.mgmt_fqdn, machine.fabric, duration)
      callback.invoke :success, :machine => machine.hostname, :result => response
    end
  end

  def cancel_downtime(machines, &block)
    callback = Support::Callback.new(&block)
    machines.each do |machine|
      response = @service.cancel_downtime(machine.mgmt_fqdn, machine.fabric)
      callback.invoke :success, :machine => machine.hostname, :result => response
    end
  end

  def register_new_machines(machines)
    sites = machines.map(&:fabric).uniq
    logger(Logger::INFO) { "running puppet on nagios servers (in #{sites}) so they will discover this node and include in monitoring" }

    fqdn_filter = "fqdn=/mgmt\\.(#{sites.join('|')})\\.net\\.local/"
    system('mco', 'puppetng', 'run', '--concurrency', '5', '--with-fact', fqdn_filter, '--with-class', 'nagios')
  end
end
