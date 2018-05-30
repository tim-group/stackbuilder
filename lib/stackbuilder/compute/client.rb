require 'stackbuilder/compute/namespace'
require 'mcollective'
require 'stackbuilder/support/mcollective'

class Compute::Client
  include Support::MCollective

  # audit_domains is not enabled by default, as it takes significant time to complete
  def audit_hosts(fabric, audit_domains = false, audit_storage = true, audit_inventory = true)
    fail "Unable to audit hosts when Fabric is nil" if fabric.nil?
    hosts = discover_compute_nodes(fabric)
    fail "unable to find any compute nodes in fabric #{fabric}" if hosts.empty?

    libvirt_response = mco_client("libvirt", :nodes => hosts) do |mco|
      mco.hvinfo.map do |hv|
        fail "all compute nodes must respond with a status code of 0 #{hv.pretty_inspect}" unless hv[:statuscode] == 0

        domains = audit_domains ? get_libvirt_domains(hv) : {}

        [hv[:sender], hv[:data].merge(:domains => domains)]
      end
    end
    fail "libvirt - not all compute nodes (#{hosts.join(', ')}) responded -- missing responses from " \
      "(#{(hosts - libvirt_response.map { |x| x[0] }).join(', ')})" unless hosts.size == libvirt_response.size

    response_hash = Hash[libvirt_response]

    if audit_inventory
      inventory_response = get_inventory(hosts)
      fail "inventory - not all hosts responded -- missing responses from " \
        "(#{(hosts - inventory_response.keys.map { |x| x[0] }).join(', ')})" unless hosts.size == inventory_response.size
      response_hash = merge_attributes_by_fqdn(response_hash, inventory_response)
    end

    if audit_storage
      storage_response = mco_client("computenodestorage", :nodes => hosts) do |mco|
        result = mco.details
        result.map do |resp|
          fail "all compute nodes must respond with a status code of 0 #{resp.pretty_inspect}" \
            unless resp[:statuscode] == 0

          [resp[:sender], { :storage => resp[:data] }]
        end
      end
      storage_response_hash = Hash[storage_response]

      fail "storage - not all compute nodes (#{hosts.join(', ')}) responded -- missing responses from " \
        "(#{(hosts - storage_response.map { |x| x[0] }).join(', ')})" unless hosts.size == storage_response.size

      response_hash.each { |fqdn, attr| response_hash[fqdn] = attr.merge(storage_response_hash[fqdn]) }
    end

    response_hash
  end

  def launch(host, specs)
    invoke :launch, specs, :timeout => 10_000, :nodes => [host]
  end

  def allocate_ips(host, specs)
    invoke :allocate_ips, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def free_ips(host, specs)
    invoke :free_ips, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def clean(fabric, specs)
    invoke :clean, specs, :timeout => 15 * 60, :fabric => fabric
  end

  def add_cnames(host, spec)
    invoke :add_cnames, spec, :timeout => 15 * 60, :nodes => [host]
  end

  def remove_cnames(host, spec)
    invoke :remove_cnames, spec, :timeout => 15 * 60, :nodes => [host]
  end

  def check_vm_definitions(host, specs)
    invoke :check_definition, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def enable_live_migration(source_host_fqdn, dest_host_fqdn)
    manage_live_migration(source_host_fqdn, dest_host_fqdn, true)
  end

  def disable_live_migration(source_host_fqdn, dest_host_fqdn)
    manage_live_migration(source_host_fqdn, dest_host_fqdn, false)
  end

  private

  def discover_compute_nodes(fabric)
    mco_client("computenode", :fabric => fabric) do |mco|
      mco.discover.sort
    end
  end

  def invoke(selector, specs, client_options)
    mco_client("computenode", client_options) do |mco|
      mco.send(selector, :specs => specs).map do |node|
        fail node[:statusmsg] if node[:statuscode] != 0

        # XXX mcollective's implemented_by, after reading the return JSON, arbitrarily converts hash keys from strings
        # to symbols. stackbuilder expects strings. the line below does the necessary conversion.
        # this workaround can lead to nasty hard to debug problems
        node.results[:data] = node.results[:data].inject({}) do |acc, (k, v)|
          acc[k.to_s] = v
          acc
        end

        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def manage_live_migration(source_host_fqdn, dest_host_fqdn, enable)
    logger(Logger::INFO) { "#{enable ? 'En' : 'Dis'}abling live migration capability from #{source_host_fqdn} to #{dest_host_fqdn}" }

    action = enable ? "enable_live_migration" : "disable_live_migration"
    responses = []
    responses += mco_client("computenode", :nodes => [source_host_fqdn]) do |mco|
      mco.send(action, :other_host => dest_host_fqdn, :direction => 'outbound')
    end
    responses += mco_client("computenode", :nodes => [dest_host_fqdn]) do |mco|
      mco.send(action, :other_host => source_host_fqdn, :direction => 'inbound')
    end
    responses.each do |response|
      success = response[:statuscode] == 0
      level = success ? Logger::DEBUG : Logger::ERROR
      logger(level) { "#{response[:sender]} = #{success ? 'OK' : 'Failed'}: #{response[:statusmsg]}" }
    end
    fail "Failed to enable live migration on hosts." if responses.count { |r| r[:statuscode] == 0 } < 2

    run_puppet_on([source_host_fqdn, dest_host_fqdn])
  end

  def run_puppet_on(hosts)
    logger(Logger::INFO) { "Triggering puppet runs on #{hosts.join(', ')}." }

    results = mco_client("puppetng", :nodes => hosts) do |mco|
      run_id = "live_migration_#{Time.now.to_i}"
      responses = mco.run(:runid => run_id)
      return responses if responses.count { |r| r[:statuscode] == 0 } < hosts.size

      loop do
        responses = mco.check_run(:runid => run_id)
        finished_hosts = responses.select { |r| r[:statuscode] == 0 && r[:data][:state] != 'waiting' && r[:data][:state] != 'running' }.
                                      map { |r| r[:sender] }
        break if finished_hosts.size == hosts.size
        logger(Logger::DEBUG) { "Waiting for puppet runs to complete on #{(hosts - finished_hosts).join(', ')}." }
        sleep 5
      end

      responses
    end

    logger(Logger::INFO) { "RESULT #{results}" }

    hosts_with_results = results.reject { |r| r[:data][:state].nil? }.map { |r| r[:sender] }
    failed_to_trigger_on = hosts - hosts_with_results
    unless failed_to_trigger_on.empty?
      logger(Logger::FATAL) { "Failed to trigger puppet on #{failed_to_trigger_on.join(', ')}" }
      fail "puppet runs could not be triggered"
    end

    failed_runs = results.reject { |r| r[:data][:state] == 'success' }
    return if failed_runs.empty?

    failed_runs.each { |run| logger(Logger::FATAL) { "Puppet run failed on #{run[:sender]}:\n  #{run[:data][:errors].join("\n  ")}" } }
    fail "puppet runs failed"
  end

  def merge_attributes_by_fqdn(source_hash, target_hash)
    source_hash.each do |fqdn, attr|
      target_hash[fqdn] = attr.merge(target_hash[fqdn])
    end
    target_hash
  end

  def get_inventory(hosts)
    mco_client('rpcutil', :nodes => hosts) do |mco|
      result = mco.inventory
      result.map do |resp|
        [resp[:sender], {
          :facts   => resp[:data][:facts],
          :classes => resp[:data][:classes],
          :agents  => resp[:data][:agents]
        }]
      end
    end.to_h
  end

  def get_libvirt_domains(hv)
    host_fqdn = hv[:sender]
    host_domain = host_fqdn.partition('.')[2]
    vm_names = hv[:data][:active_domains] + hv[:data][:inactive_domains]

    host_volumes = (mco_client("lvm", :nodes => [host_fqdn]) do |mco|
      mco.lvs.map do |lvs|
        fail "failed to get logical volume info for #{host_fqdn}: #{lvs[:statusmsg]}" if lvs[:statuscode] != 0
        lvs[:data][:lvs]
      end
    end).flatten
    fail "Got no response from mcollective lvs.lvm request to #{host_fqdn}" if !vm_names.empty? && host_volumes.empty?

    result = mco_client("libvirt", :timeout => 1, :nodes => [host_fqdn]) do |mco|
      vm_names.map do |vm_name|
        result = {}
        result.merge!(get_vm_info(mco, vm_name))
        result.merge!(:logical_volumes => host_volumes.select { |lv| lv[:lv_name].start_with?(vm_name) })

        vm_fqdn = "#{vm_name}.#{host_domain}"
        { vm_fqdn => result }
      end.reduce({}, :merge)
    end

    inventory = get_inventory(vm_names.map { |name| "#{name}.#{host_domain}" })
    merge_attributes_by_fqdn(inventory, result)
  end

  def get_vm_info(mco, vm_name, attempts = 3)
    vm_info = mco.domaininfo(:domain => vm_name).map do |di|
      fail "domainfo request #{vm_name} failed: #{di[:statusmsg]}" if di[:statuscode] != 0 && attempts == 1
      di[:statuscode] == 0 ? di[:data] : nil
    end

    if vm_info.empty? || vm_info[0].nil?
      return get_vm_info(mco, vm_name, attempts - 1) if attempts > 1
      fail "Got no response for domainfo request #{vm_name}"
    end

    vm_info[0]
  end
end
