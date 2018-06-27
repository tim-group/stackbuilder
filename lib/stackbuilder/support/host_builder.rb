require 'stackbuilder/support/namespace'

class Support::HostBuilder
  def initialize(factory, nagios)
    @factory = factory
    @nagios = nagios
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
    build(host_fqdn)
  end

  private

  def build(host_fqdn)
    # check host exists and is powered off
    # retrieve mac address and setup PXE

    logger(Logger::INFO) { "About to install o/s on #{host_fqdn}" }
    # instigate rebuild

    # clean/wait/sign puppet cert
    # sanity check
    # enable allocation
  end

  def bail(msg)
    logger(Logger::FATAL) { msg }
    exit 1
  end
end
