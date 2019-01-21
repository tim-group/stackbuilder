require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_puppet'

class Support::Puppet
  def initialize(subscription)
    @mcollective_puppet = Support::MCollectivePuppet.new
    @subscription = subscription
  end

  def do_puppet_run_on_dependencies(machine_def)
    all_dependencies = Set.new
    machine_def.accept do |m|
      all_dependencies += m.dependent_nodes if m.is_a? Stacks::MachineDef
    end

    dependency_fqdns = []
    all_dependencies.map do |dependency|
      dependency.accept do |m|
        if m.is_a? Stacks::MachineDef
          dependency_fqdns << m.mgmt_fqdn if m.should_prepare_dependency?
        end
      end
    end

    dependency_fqdns = dependency_fqdns.sort.uniq

    require 'tempfile'
    Tempfile.open("mco_prepdeps") do |f|
      f.puts dependency_fqdns.join("\n")
      f.flush

      system('mco', 'puppetng', 'run', '--concurrency', '5', '--nodes', f.path)
    end
  end

  # wait for automatic otp signing of outstanding Puppet certificates for these machines
  def puppet_wait_for_autosign(machine_def)
    fqdns_to_sign = get_machine_fqdns(machine_def, "signing")

    start_time = Time.now
    result = @subscription.wait_for_hosts("provision.*", fqdns_to_sign, 600)
    result.all.each do |vm, status|
      level = (status == "success") ? Logger::INFO : Logger::ERROR
      logger(level) { "puppet cert signing: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end
    result
  end

  # sign outstanding Puppet certificate signing requests for these machines
  def puppet_poll_sign(machine_def)
    poll_sign(get_machine_fqdns(machine_def, "poll signing"))
  end

  def poll_sign(host_fqdns, timeout = 450)
    success = false
    @mcollective_puppet.ca_sign(host_fqdns, timeout) do
      on :success do |machine|
        logger(Logger::INFO) { "successfully signed cert for #{machine}" }
        success = true
      end
      on :failed do |machine|
        logger(Logger::WARN) { "failed to signed cert for #{machine}" }
      end
      on :unaccounted do |machine|
        logger(Logger::WARN) { "cert not signed for #{machine} (unaccounted for)" }
      end
      on :already_signed do |machine|
        logger(Logger::WARN) { "cert for #{machine} already signed, skipping" }
        success = true
      end
    end
    success
  end

  # wait for puppet to complete its run on these machines
  def puppet_wait_for_run_completion(machine_def)
    host_fqdns = get_machine_fqdns(machine_def)
    wait_for_run_completion(host_fqdns)
  end

  def wait_for_run_completion(host_fqdns, timeout = 5400, expect_failure = false)
    start_time = Time.now

    run_result = @subscription.wait_for_hosts("puppet_status", host_fqdns, timeout)

    run_result.all.each do |vm, status|
      level = (status == "success" || expect_failure) ? Logger::INFO : Logger::ERROR
      logger(level) { "puppet run: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end

    run_result
  end

  # Remove signed certs from puppetserver
  def puppet_clean(machine_def)
    clean(get_machine_fqdns(machine_def, "removal of cert"))
  end

  def clean(fqdns_to_clean)
    @mcollective_puppet.ca_clean(fqdns_to_clean) do
      on :success do |machine|
        logger(Logger::INFO) { "successfully removed cert for #{machine}" }
      end
      on :failed do |machine|
        logger(Logger::WARN) { "failed to remove cert for #{machine}" }
      end
    end
  end

  private

  def get_machine_fqdns(machine_def, filter_needs_signing = nil)
    host_fqdns = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        if child_machine_def.needs_signing? || filter_needs_signing.nil?
          host_fqdns << child_machine_def.mgmt_fqdn
        else
          logger(Logger::INFO) { "#{filter_needs_signing} not needed for #{child_machine_def.mgmt_fqdn}" }
        end
      end
    end
    host_fqdns
  end
end
