require 'stackbuilder/support/namespace'
require 'stackbuilder/support/callback'
require 'stackbuilder/support/mcollective_nagsrv'

class Support::Nagios
  def do_nagios_register_new(machine_def)
    machines = machines_from(machine_def)
    nagios_helper = Support::NagiosService.new
    nagios_helper.register_new_machines(machines.map(&:fabric).uniq)
  end

  def register_new_machine_in(fabric)
    nagios_helper = Support::NagiosService.new
    nagios_helper.register_new_machines([fabric])
  end

  def nagios_schedule_downtime(machine_def)
    machines = machines_from(machine_def)

    nagios_helper = Support::NagiosService.new
    downtime_secs = 1800 # 1800 = 30 mins
    nagios_helper.schedule_downtime(machines, downtime_secs) do
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

  def nagios_schedule_uptime(machine_def)
    machines = machines_from(machine_def)

    nagios_helper = Support::NagiosService.new
    nagios_helper.force_checks(machines) do
      on :success do |response_hash|
        logger(Logger::INFO) do
          "successfully forced checks for #{response_hash[:machine]} " \
        "result: #{response_hash[:result]}"
        end
      end
      on :failed do |response_hash|
        logger(Logger::INFO) do
          "failed to force checks for #{response_hash[:machine]} " \
        "result: #{response_hash[:result]}"
        end
      end
    end
    nagios_helper.schedule_downtime(machines, 60) do
      on :success do |response_hash|
        logger(Logger::INFO) do
          "successfully reduced scheduled downtime for #{response_hash[:machine]} " \
        "result: #{response_hash[:result]}"
        end
      end
      on :failed do |response_hash|
        logger(Logger::INFO) do
          "failed to reduce scheduled downtime for #{response_hash[:machine]} " \
        "result: #{response_hash[:result]}"
        end
      end
    end
  end

  def nagios_cancel_downtime(machine_def)
    machines = machines_from(machine_def)

    nagios_helper = Support::NagiosService.new
    nagios_helper.cancel_downtime(machines) do
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

  def schedule_host_downtime(host_fqdn, fabric, downtime_secs = 1800)
    nagios_helper = Support::NagiosService.new
    result = nagios_helper.schedule_host_downtime(host_fqdn, fabric, downtime_secs)
    logger(Logger::INFO) { "scheduled #{downtime_secs}s downtime for #{host_fqdn}: #{result}" }
  end

  def schedule_host_uptime(host_fqdn, fabric, delay = 60)
    nagios_helper = Support::NagiosService.new
    nagios_helper.force_host_checks(host_fqdn, fabric)
    result = nagios_helper.schedule_host_downtime(host_fqdn, fabric, delay)
    logger(Logger::INFO) { "reduced scheduled downtime for #{host_fqdn} to #{delay}s: #{result}" }
  end

  def cancel_host_downtime(host_fqdn, fabric)
    nagios_helper = Support::NagiosService.new
    result = nagios_helper.cancel_host_downtime(host_fqdn, fabric)
    logger(Logger::INFO) { "cancelled downtime for #{host_fqdn}: #{result}" }
  end

  private

  def machines_from(machine_def)
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

  def force_checks(machines, &block)
    callback = Support::Callback.new(&block)
    machines.each do |machine|
      response = @service.force_checks(machine.mgmt_fqdn, machine.fabric)
      callback.invoke :success, :machine => machine.hostname, :result => response
    end
  end

  def schedule_host_downtime(host_fqdn, fabric, duration = 600)
    @service.schedule_downtime(host_fqdn, fabric, duration)
  end

  def cancel_host_downtime(host_fqdn, fabric)
    @service.cancel_downtime(host_fqdn, fabric)
  end

  def force_host_checks(host_fqdn, fabric)
    @service.force_checks(host_fqdn, fabric)
  end

  def register_new_machines(fabrics)
    logger(Logger::INFO) { "running puppet on nagios servers (in #{fabrics}) so they will discover this node and include in monitoring" }

    fqdn_filter = "fqdn=/mgmt\\.(#{fabrics.join('|')})\\.net\\.local/"
    system('mco', 'puppetng', 'run', '--concurrency', '5', '--with-fact', fqdn_filter, '--with-class', 'nagios')
  end
end
