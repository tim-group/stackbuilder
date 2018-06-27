require 'stackbuilder/support/namespace'

class Support::HostBuilder
  def initialize(factory)
    @factory = factory
  end

  def rebuild(host_fqdn)
    hostname = host_fqdn.partition('.').first
    fabric = hostname.partition('-').first
    host = @factory.host_repository.find_compute_nodes(fabric, false, false, false).hosts.find { |h| h.hostname == hostname }

    bail "unable to find #{hostname}" if host.nil?

    logger(Logger::INFO) { "Will rebuild: #{host.fqdn}" }

    # check host is empty
    # set allocation disabled
    # schedule downtime
    # remove from mco mongodb registry
    # power off

    build(host_fqdn)

    # unschedule downtime

    bail("not implemented")
  end

  def build_new(host_fqdn)
    build(host_fqdn)
  end

  private

  def build(host_fqdn)
    # check host exists and is powered off
    # retrieve mac address and setup PXE
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
