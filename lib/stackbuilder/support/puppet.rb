require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/callback'

class PuppetCtl
  include Support::MCollectivePuppet
  # sign outstanding puppet certificate signing requests for these machines
  def sign(machine_def)
    logger(Logger::DEBUG) { "inside \"#{__method__}\", machine_def = \"#{machine_def.name}\"" }
    puppet_certs_to_sign = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        if child_machine_def.needs_signing?
          puppet_certs_to_sign << child_machine_def.mgmt_fqdn
        else
          logger(Logger::INFO) { "signing not needed for #{child_machine_def.mgmt_fqdn}" }
        end
      end
    end
    start_time = Time.now
    subscription = Subscription.new
    subscription.start(["provision.*", "puppet_status"])
    result = subscription.wait_for_hosts("provision.*", puppet_certs_to_sign, 600)
    result.all.each do |vm, status|
      logger(Logger::INFO) { "puppet cert signing: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end
  end

  # sign outstanding puppet certificate signing requests for these machines
  def poll_sign(machine_def)
    logger(Logger::DEBUG) { "inside \"#{__method__}\", machine_def = \"#{machine_def.name}\"" }
    puppet_certs_to_sign = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        if child_machine_def.needs_poll_signing?
          puppet_certs_to_sign << child_machine_def.mgmt_fqdn
        else
          logger(Logger::INFO) { "poll signing not needed for #{child_machine_def.mgmt_fqdn}" }
        end
      end
    end

    ca_sign(puppet_certs_to_sign) do
      on :success do |machine|
        logger(Logger::INFO) { "successfully signed cert for #{machine}" }
      end
      on :failed do |machine|
        logger(Logger::WARN) { "failed to signed cert for #{machine}" }
      end
      on :unaccounted do |machine|
        logger(Logger::WARN) { "cert not signed for #{machine} (unaccounted for)" }
      end
      on :already_signed do |machine|
        logger(Logger::WARN) { "cert for #{machine} already signed, skipping" }
      end
    end
  end

  # wait for puppet to complete its run on these machines
  def wait(machine_def)
    logger(Logger::DEBUG) { "inside \"#{__method__}\", machine_def = \"#{machine_def.name}\"" }
    start_time = Time.now
    hosts = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        hosts << child_machine_def.mgmt_fqdn
      end
    end

    subscription = Subscription.new
    subscription.start(["provision.*", "puppet_status"])
    run_result = subscription.wait_for_hosts("puppet_status", hosts, 5400)

    run_result.all.each do |vm, status|
      logger(Logger::INFO) { "puppet run: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end

    unless run_result.all_passed?
      fail("Puppet runs have timed out or failed, see above for details")
    end
  end

  # run puppet on these machines
  def run(machine_def)
    logger(Logger::DEBUG) { "inside \"#{__method__}\", machine_def = \"#{machine_def.name}\"" }
    hosts = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        hosts << child_machine_def.mgmt_fqdn
      end
    end

    success = mco_client("puppetd") do |mco|
      engine = PuppetRoll::Engine.new({ :concurrency => 5 }, [], hosts, PuppetRoll::Client.new(hosts, mco))
      engine.execute
      pp engine.get_report
      engine.successful?
    end

    fail("some nodes have failed their puppet runs") unless success
  end

  # remove signed certs from puppetmaster
  def clean(machine_def)
    logger(Logger::DEBUG) { "inside \"#{__method__}\", machine_def = \"#{machine_def.name}\"" }
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
end
