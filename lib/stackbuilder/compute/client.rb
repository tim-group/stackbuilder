require 'stackbuilder/compute/namespace'
require 'mcollective'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/mcollective_libvirt'
require 'stackbuilder/support/mcollective_rpcutil'
require 'stackbuilder/support/mcollective_lvm'
require 'stackbuilder/support/mcollective_puppetng'

class Compute::Client
  include Support::MCollective

  def initialize()
    @mco_libvirt = Support::MCollectiveLibvirt.new
    @mco_rpcutil = Support::MCollectiveRpcutil.new
    @mco_lvm = Support::MCollectiveLvm.new
    @mco_puppetng = Support::MCollectivePuppetng.new
  end

  def audit_fabric(fabric, audit_domains = false, audit_storage = true, audit_inventory = true)
    fail "Unable to audit hosts when Fabric is nil" if fabric.nil?
    hosts = discover_compute_nodes(fabric)
    fail "unable to find any compute nodes in fabric #{fabric}" if hosts.empty?
    audit_hosts(hosts, audit_domains, audit_storage, audit_inventory)
  end

  # audit_domains is not enabled by default, as it takes significant time to complete
  def audit_hosts(host_fqdns, audit_domains = false, audit_storage = true, audit_inventory = true)
    libvirt_response = @mco_libvirt.hvinfo(host_fqdns)

    response_hash = Hash[libvirt_response]
    if audit_domains
      response_hash.each do |host_fqdn, hv|
        vm_names = hv[:active_domains] + hv[:inactive_domains]
        response_hash[host_fqdn][:domains] = audit_domains(host_fqdn, vm_names)
      end
    end

    if audit_inventory
      inventory_response = @mco_rpcutil.get_inventory(host_fqdns)
      fail "inventory - not all hosts responded -- missing responses from " \
        "(#{(host_fqdns - inventory_response.keys.map { |x| x[0] }).join(', ')})" unless host_fqdns.size == inventory_response.size
      response_hash = merge_attributes_by_fqdn(response_hash, inventory_response)
    end

    if audit_storage
      storage_response = mco_client("computenodestorage", :nodes => host_fqdns) do |mco|
        result = mco.details
        result.map do |resp|
          fail "all compute nodes must respond with a status code of 0 #{resp.pretty_inspect}" \
            unless resp[:statuscode] == 0

          [resp[:sender], { :storage => resp[:data] }]
        end
      end
      storage_response_hash = Hash[storage_response]

      fail "storage - not all compute nodes (#{host_fqdns.join(', ')}) responded -- missing responses from " \
        "(#{(host_fqdns - storage_response.map { |x| x[0] }).join(', ')})" unless host_fqdns.size == storage_response.size

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

  def add_cnames(host, specs)
    invoke :add_cnames, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def remove_cnames(host, specs)
    invoke :remove_cnames, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def check_vm_definitions(host, specs)
    invoke :check_definition, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def create_storage(host, specs)
    invoke :create_storage, specs, :timeout => 15 * 60, :nodes => [host]
  end

  def enable_live_migration(source_host_fqdn, dest_host_fqdn)
    manage_live_migration(source_host_fqdn, dest_host_fqdn, true)
  end

  def disable_live_migration(source_host_fqdn, dest_host_fqdn)
    manage_live_migration(source_host_fqdn, dest_host_fqdn, false)
  end

  def live_migrate_vm(source_host_fqdn, dest_host_fqdn, vm_name)
    migrate_vm(source_host_fqdn, dest_host_fqdn, vm_name)
  end

  def clean_post_migration(source_host_fqdn, spec)
    archive_vm(source_host_fqdn, spec)
  end

  def enable_allocation(host_fqdn)
    resps = mco_client("computenode", :nodes => [host_fqdn]) { |mco| mco.enable_allocation }
    fail "no response to mco computenode.enable_allocation request" unless resps.size == 1
    fail "mco computenode.enable_allocation request railed: #{resps[0][:statusmsg]}" unless resps[0][:statuscode] == 0
    resps[0]
  end

  def disable_allocation(host_fqdn, reason)
    resps = mco_client("computenode", :nodes => [host_fqdn]) { |mco| mco.disable_allocation(:reason => reason) }
    fail "no response to mco computenode.disable_allocation request" unless resps.size == 1
    fail "mco computenode.disable_allocation request railed: #{resps[0][:statusmsg]}" unless resps[0][:statuscode] == 0
    resps[0]
  end

  private

  def discover_compute_nodes(fabric)
    mco_client("computenode", :fabric => fabric) { |mco| mco.discover.sort }
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

    tags = ["live_migration_setup"]
    tags << "purge_unmanaged_firewall_rules" unless enable
    @mco_puppetng.run_puppet([dest_host_fqdn], tags)
  end

  def migrate_vm(source_host_fqdn, dest_host_fqdn, vm_name)
    launch_responses = mco_client("computenode", :nodes => [source_host_fqdn]) do |mco|
      mco.live_migrate_vm(:other_host => dest_host_fqdn, :vm_name => vm_name)
    end
    fail "no response from live migration mco call" unless launch_responses.size == 1
    response = launch_responses.first
    fail "failed to perform live migration #{response[:statusmsg]}" unless response[:statuscode] == 0
    fail "failed to perform live migration" unless response[:data][:state] == 'running'

    completion_response = mco_client("computenode", :nodes => [source_host_fqdn]) do |mco|
      chk_resps = []
      loop do
        chk_resps = mco.check_live_vm_migration(:vm_name => vm_name)
        break if chk_resps.size == 1 && chk_resps.first[:statuscode] == 0 && chk_resps.first[:data][:state] != 'running'
        percentage = chk_resps.first[:data][:progress_percentage]
        message =  "  #{percentage.nil? ? 0 : percentage}% complete"
        dji = chk_resps.first[:data][:domjobinfo]
        unless dji.nil? || dji.empty?
          message += " (#{format_dji(dji, 'memory')} RAM; #{format_dji(dji, 'file')} disk)"
        end
        STDERR.printf("%s\r", message.ljust(60))
        sleep 5
      end
      STDERR.printf("%s\n", "live migration finished".ljust(60))
      chk_resps.first
    end

    return if completion_response[:data][:state] == 'successful'

    logger(Logger::FATAL) { "Live migration failed, see /var/log/live_migration/#{vm_name}-current on #{source_host_fqdn} for more info" }
    fail "Failed to complete live migration"
  end

  def format_dji(domjobinfo, item_name)
    processed = domjobinfo[(item_name + "_processed").to_sym]
    total = domjobinfo[(item_name + "_total").to_sym]
    return "?" if processed.nil? || total.nil?

    processed_val_and_unit = processed.split(" ", 2)
    total_val_and_unit = total.split(" ", 2)
    return "?" if processed_val_and_unit.size == 1 || total_val_and_unit.size == 1

    processed_val = processed_val_and_unit[0].to_f
    total_val = total_val_and_unit[0].to_f
    return "?" if total_val == 0.0

    if processed_val_and_unit[1] != total_val_and_unit[1]
      processed_val = convert_val(processed_val, processed_val_and_unit[1].to_sym, total_val_and_unit[1].to_sym)
    end

    percentage = processed_val / total_val * 100.0
    sprintf("%.0f%% of %.0f%s", percentage, total_val, total_val_and_unit[1])
  end

  def convert_val(val, from_unit, to_unit)
    units = [:B, :KiB, :MiB, :GiB, :TiB]
    i1 = units.find_index(from_unit)
    i2 = units.find_index(to_unit)
    return 0.0 if i2.nil? || i1.nil?
    val * 1024.0**(i1 - i2)
  end

  def archive_vm(source_host_fqdn, spec)
    mco_client("computenode", :nodes => [source_host_fqdn]) do |mco|
      logger(Logger::INFO) { "Cleaning VM definition and transient storage" }
      responses = mco.clean(:specs => [spec])
      fail "no response from clean mco call" unless responses.size == 1
      response = responses.first
      fail "failed to clean vm #{response[:statusmsg]}" unless response[:statuscode] == 0

      logger(Logger::INFO) { "Archiving persistent storage" }
      responses = mco.archive_persistent_storage(:specs => [spec])
      fail "no response from archive_persistent_storage mco call" unless responses.size == 1
      response = responses.first
      fail "failed to archive persistent storage for vm #{response[:statusmsg]}" unless response[:statuscode] == 0
    end
  end

  def merge_attributes_by_fqdn(source_hash, target_hash)
    source_hash.each do |fqdn, attr|
      target_hash[fqdn] = attr.merge(target_hash.fetch(fqdn, {}))
    end
    target_hash
  end

  def audit_domains(host_fqdn, vm_names)
    return {} if vm_names.empty?

    host_domain = host_fqdn.partition('.')[2]
    vm_name_by_vm_fqdn = Hash[vm_names.map { |name| ["#{name}.#{host_domain}", name] }]

    inventory = @mco_rpcutil.get_inventory(vm_name_by_vm_fqdn.keys)
    host_volumes = @mco_lvm.logical_volumes(host_fqdn)
    domain_info = @mco_libvirt.domaininfo(host_fqdn, vm_names)

    Hash[vm_name_by_vm_fqdn.map do |vm_fqdn, vm_name|
      data = { :logical_volumes => host_volumes.select { |lv| lv[:lv_name].start_with?(vm_name) } }
      data.merge!(domain_info[vm_name])
      data.merge!(inventory[vm_fqdn]) if inventory[vm_fqdn]
      [vm_fqdn, data]
    end]
  end
end
