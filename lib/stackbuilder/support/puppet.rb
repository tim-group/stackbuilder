require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective_puppet'

class Support::Puppet
  def initialize
    @mcollective_puppet = Support::MCollectivePuppet.new
  end

  def do_puppet_run_on_dependencies(machine_def)
    all_dependencies = Set.new
    machine_def.accept do |m|
      all_dependencies += m.dependencies.flatten if m.is_a? Stacks::MachineDef
    end

    dependency_fqdns = []
    all_dependencies.map do |dependency|
      dependency.accept do |m|
        dependency_fqdns << m.mgmt_fqdn if m.is_a? Stacks::MachineDef
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

  # sign outstanding Puppet certificate signing requests for these machines
  def puppet_sign(machine_def, subscription)
    fqdns_to_sign = get_machine_fqdns(machine_def, "signing")

    start_time = Time.now
    result = subscription.wait_for_hosts("provision.*", fqdns_to_sign, 600)
    result.all.each do |vm, status|
      logger(Logger::INFO) { "puppet cert signing: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end
  end

  # sign outstanding Puppet certificate signing requests for these machines
  def puppet_poll_sign(machine_def)
    fqdns_to_sign = get_machine_fqdns(machine_def, "poll signing")

    @mcollective_puppet.ca_sign(fqdns_to_sign) do
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
  def puppet_wait(machine_def, subscription)
    start_time = Time.now
    host_fqdns = get_machine_fqdns(machine_def)

    run_result = subscription.wait_for_hosts("puppet_status", host_fqdns, 5400)

    run_result.all.each do |vm, status|
      logger(Logger::INFO) { "puppet run: #{status} for #{vm} - (#{Time.now - start_time} sec)" }
    end

    run_result
  end

  # Remove signed certs from puppetserver
  def puppet_clean(machine_def)
    fqdns_to_clean = get_machine_fqdns(machine_def, "removal of cert")

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
