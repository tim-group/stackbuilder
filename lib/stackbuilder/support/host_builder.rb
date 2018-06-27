require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_pxe'

class Support::HostBuilder
  def initialize(factory, nagios)
    @factory = factory
    @nagios = nagios
    @pxe = Support::MCollectivePxe.new
  end

  def rebuild(host_fqdn)
    hostname = host_fqdn.partition('.').first
    fabric = hostname.partition('-').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, true).hosts.find { |h| h.hostname == hostname }

    bail "unable to find #{host_fqdn}" if host.nil?
    bail "cannot rebuild #{host_fqdn}, it has VMs: #{host.machines.map { |m| m[:hostname] }.join(', ')}" unless host.machines.empty?
    bail "cannot rebuild #{host_fqdn}, it has allocation enabled" unless host.facts['allocation_disabled']

    @nagios.schedule_host_downtime(host_fqdn, fabric)
    # remove from mco mongodb registry
    # power off

    logger(Logger::INFO) { "Will rebuild #{host.fqdn}" }
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

    # check host exists and is powered off

    # retrieve mac address
    mac_address = '3c-d9-2b-f9-48-8c'

    @pxe.prepare_for_reimage(mac_address, fabric)
    begin
      logger(Logger::INFO) { "About to install o/s on #{host_fqdn}" }
      # instigate rebuild
    ensure
      @pxe.cleanup_after_reimage(mac_address, fabric)
    end

    # clean/wait/sign puppet cert
    # sanity check
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
