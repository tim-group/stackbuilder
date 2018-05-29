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
