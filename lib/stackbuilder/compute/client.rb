require 'stackbuilder/compute/namespace'
require 'mcollective'
require 'stackbuilder/support/mcollective'

class Compute::Client
  include Support::MCollective

  def get_inventory(hosts)
    response = mco_client('rpcutil', :nodes => hosts) do |mco|
      result = mco.inventory
      result.map do |resp|
        [resp[:sender], {
          :facts   => resp[:data][:facts],
          :classes => resp[:data][:classes],
          :agents  => resp[:data][:agents]
        }]
      end
    end
    response
  end

  def merge_attributes_by_fqdn(source_hash, target_hash)
    source_hash.each do |fqdn, attr|
      target_hash[fqdn] = attr.merge(target_hash[fqdn])
    end
    target_hash
  end

  def get_libvirt_domains(hv)
    domain_name = hv[:sender].gsub(/^[^.]*\.mgmt\./, "")

    host_volumes = (mco_client("lvm", :nodes => [hv[:sender]]) do |lvm|
      lvm.lvs.map do |lvs|
        fail "failed to get logical volume info for #{hv[:sender]}: #{lvm[:statusmsg]}" if lvs[:statuscode] != 0
        lvs[:data][:lvs]
      end
    end).flatten

    mco_client("libvirt", :nodes => [hv[:sender]]) do |mco|
      (hv[:data][:active_domains] + hv[:data][:inactive_domains]).map do |d|
        result = {}

        vm_info = mco.domaininfo(:domain => d).map do |di|
          di[:data] if di[:statuscode] == 0
        end

        # retry once
        if vm_info.empty?
          vm_info = mco.domaininfo(:domain => d).map do |di|
            fail "domainfo request #{hv[:sender]} #{d} failed: #{di[:statusmsg]}" if di[:statuscode] != 0
            di[:data]
          end
        end
        fail "Got no response for domainfo request #{hv[:sender]} #{d}" if vm_info.empty?

        result.merge!(vm_info[0])
        result.merge!(:logical_volumes => host_volumes.select { |lv| lv[:lv_name].start_with?(d) })

        vm_fqdn = d + "." + domain_name
        { vm_fqdn => result }
      end.reduce({}, :merge)
    end
  end

  # audit_domains is not enabled by default, as it takes significant time to complete
  def audit_hosts(fabric, audit_domains = false)
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
    fail "libvirt - not all compute nodes (#{hosts.join(', ')}) responded -- got responses from " \
      "(#{libvirt_response.map { |x| x[0] }.join(', ')})" unless hosts.size == libvirt_response.size

    response_hash = Hash[libvirt_response]

    inventory_response = get_inventory(hosts)
    fail "inventory - not all compute nodes (#{hosts.join(', ')}) responded -- got responses from " \
      "(#{inventory_response.map { |x| x[0] }.join(', ')})" unless hosts.size == inventory_response.size

    response_hash = merge_attributes_by_fqdn(response_hash, Hash[inventory_response])

    storage_response = mco_client("computenodestorage", :nodes => hosts) do |mco|
      result = mco.details
      result.map do |resp|
        fail "all compute nodes must respond with a status code of 0 #{resp.pretty_inspect}" \
          unless resp[:statuscode] == 0

        [resp[:sender], { :storage => resp[:data] }]
      end
    end
    storage_response_hash = Hash[storage_response]

    fail "storage - not all compute nodes (#{hosts.join(', ')}) responded -- got responses from " \
      "(#{storage_response.map { |x| x[0] }.join(', ')})" unless hosts.size == storage_response.size

    response_hash.each { |fqdn, attr| response_hash[fqdn] = attr.merge(storage_response_hash[fqdn]) }
  end

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
end
