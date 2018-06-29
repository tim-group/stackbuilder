require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_pxe'
require 'stackbuilder/support/mcollective_hpilo'
require 'stackbuilder/support/mcollective_rpcutil'
require 'stackbuilder/support/mcollective_hostcleanup'

class Support::HostBuilder
  def initialize(factory, nagios, puppet)
    @factory = factory
    @nagios = nagios
    @puppet = puppet
    @pxe = Support::MCollectivePxe.new
    @hpilo = Support::MCollectiveHpilo.new
    @rpcutil = Support::MCollectiveRpcutil.new
    @hostcleanup = Support::MCollectiveHostcleanup.new
  end

  def rebuild(host_fqdn)
    ensure_safe_to_nuke(host_fqdn)

    fabric = host_fqdn.partition('-').first
    logger(Logger::INFO) { "will rebuild #{host_fqdn}, scheduling downtime and powering off host" }
    @nagios.schedule_host_downtime(host_fqdn, fabric, 60 * 40)
    @hpilo.power_off_host(host_fqdn, fabric)
    @hostcleanup.hostcleanup(host_fqdn, "mongodb")

    build(host_fqdn)

    logger(Logger::INFO) { "rebuild complete, cancelling downtime" }
    @nagios.cancel_host_downtime(host_fqdn, fabric)
  end

  def build_new(host_fqdn)
    fabric = host_fqdn.partition('-').first
    build(host_fqdn)

    logger(Logger::INFO) { "build complete, registering new machine with nagios" }
    @nagios.register_new_machine_in(fabric)
  end

  private

  def ensure_safe_to_nuke(host_fqdn)
    host = get_and_check_host(host_fqdn)

    unless host.facts['allocation_disabled']
      logger(Logger::INFO) { 'disabling allocation' }
      @factory.compute_node_client.disable_allocation(host_fqdn, "rebuilding kvm host")
      host = get_and_check_host(host_fqdn)
    end

    bail "cannot rebuild #{host_fqdn}, it has allocation enabled" unless host.facts['allocation_disabled']
  end

  def get_and_check_host(host_fqdn)
    hostname = host_fqdn.partition('.').first
    fabric = host_fqdn.partition('-').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, true).hosts.find {|h| h.hostname == hostname}
    bail "unable to find #{host_fqdn}" if host.nil?
    bail "cannot rebuild #{host_fqdn}, it has VMs: #{host.machines.map {|m| m[:hostname]}.join(', ')}" unless host.machines.empty?
    host
  end

  def build(host_fqdn)
    fabric = host_fqdn.partition('-').first

    bail "#{host_fqdn} is not off" unless @hpilo.get_host_power_status(host_fqdn, fabric) == "OFF"

    logger(Logger::INFO) { "preparing to install new o/s on #{host_fqdn}" }
    mac_address = @hpilo.get_mac_address(host_fqdn, fabric)
    @pxe.prepare_for_reimage(mac_address, fabric)
    begin
      @hpilo.update_ilo_firmware(host_fqdn, fabric)
      @puppet.clean([host_fqdn])
      @hpilo.set_one_time_network_boot(host_fqdn, fabric)

      logger(Logger::INFO) { "powering on #{host_fqdn} for PXE network boot" }
      @hpilo.power_on_host(host_fqdn, fabric)

      sleep 780 # give the host 13 mins to boot up and install the vanilla o/s
      logger(Logger::INFO) { "o/s should be installed... beginning polling to sign puppet certificate" }

      signed_successfully = @puppet.poll_sign([host_fqdn], 600)
      bail "unable to sign puppet cert" unless signed_successfully
    ensure
      @pxe.cleanup_after_reimage(mac_address, fabric)
    end

    # puppet is triggered twice: the first run fails but sets up networking; the second run should pass.
    logger(Logger::INFO) { "waiting for first puppet run to complete" }
    @puppet.wait_for_run_completion([host_fqdn])
    logger(Logger::INFO) { "waiting for second puppet run to complete" }
    puppet_result = @puppet.wait_for_run_completion([host_fqdn])

    bail "puppet run did not complete" unless puppet_result.unaccounted_for.empty?
    bail "puppet run failed" unless puppet_result.failed.empty?
    bail "puppet did not succeed" if puppet_result.passed.empty?

    logger(Logger::INFO) { "puppet runs complete, waiting for final reboot" }
    wait_for_reboot(host_fqdn, 360)

    logger(Logger::INFO) { "host is up, performing checks" }
    verify_build(host_fqdn)

    logger(Logger::INFO) { "host checks successful, enabling allocation" }
    @factory.compute_node_client.enable_allocation(host_fqdn)
  end

  def wait_for_reboot(host_fqdn, timeout)
    start_time = Time.now
    until @rpcutil.ping(host_fqdn, 1).nil?
      bail "timed out waiting for host to go down" if Time.now - start_time > timeout
      sleep 10
    end

    while @rpcutil.ping(host_fqdn, 1).nil?
      bail "timed out waiting for host to come up" if Time.now - start_time > timeout
      sleep 10
    end
  end

  def verify_build(host_fqdn)
    hostname = host_fqdn.partition('.').first
    fabric = host_fqdn.partition('-').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, true).hosts.find { |h| h.hostname == hostname }
    bail "unable to find #{host_fqdn}" if host.nil?
    bail "host came up, but with allocation already enabled #{host_fqdn}" unless host.facts['allocation_disabled']
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
