require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_pxe'

class Support::HostBuilder
  def initialize(factory, nagios)
    @factory = factory
    @nagios = nagios
    @pxe = Support::MCollectivePxe.new
    @hpilo = Support::MCollectiveHpilo.new
    @hostcleanup = Support::MCollectiveHostcleanup.new
  end

  def rebuild(host_fqdn)
    hostname = host_fqdn.partition('.').first
    fabric = hostname.partition('-').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, true).hosts.find { |h| h.hostname == hostname }

    bail "unable to find #{host_fqdn}" if host.nil?
    bail "cannot rebuild #{host_fqdn}, it has VMs: #{host.machines.map { |m| m[:hostname] }.join(', ')}" unless host.machines.empty?
    bail "cannot rebuild #{host_fqdn}, it has allocation enabled" unless host.facts['allocation_disabled']

    logger(Logger::INFO) { "Will rebuild #{host_fqdn}" }
    @nagios.schedule_host_downtime(host_fqdn, fabric)
    @hostcleanup.hostcleanup(host_fqdn, "mongodb")
    @hpilo.power_off_host(host_fqdn, fabric)

    build(host_fqdn)

    @nagios.cancel_host_downtime(host_fqdn, fabric)
  end

  def build_new(host_fqdn)
    fabric = host_fqdn.partition('-').first
    build(host_fqdn)
    @nagios.register_new_machine_in(fabric)
  end

  private

  def build(host_fqdn)
    fabric = host_fqdn.partition('-').first

    bail "#{host_fqdn} is not off" unless @hpilo.get_host_power_status(host_fqdn, fabric) == "OFF"

    mac_address = @hpilo.get_mac_address(host_fqdn, fabric)
    @pxe.prepare_for_reimage(mac_address, fabric)
    begin
      logger(Logger::INFO) { "About to install o/s on #{host_fqdn}" }
      @hpilo.update_ilo_firmware(host_fqdn, fabric)
      @hpilo.set_one_time_network_boot(host_fqdn, fabric)
      @hpilo.power_on_host(host_fqdn, fabric)
    ensure
      @pxe.cleanup_after_reimage(mac_address, fabric)
    end

    # clean/wait/sign puppet cert

    verify_build(host_fqdn)
    # enable allocation
  end

  def verify_build(host_fqdn)
    # sanity check
    #   - check puppet last run report

    hostname = host_fqdn.partition('.').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, true).hosts.find { |h| h.hostname == hostname }
    bail "unable to find #{host_fqdn}" if host.nil?
    bail "host came up, but with allocation already enabled #{host_fqdn}" unless host.facts['allocation_disabled']
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
