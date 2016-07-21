require 'stackbuilder/compute/namespace'
require 'mcollective'
require 'stackbuilder/support/mcollective'

class Compute::Client
  include Support::MCollective

  def get_fact(fact, hosts)
    fact_response = mco_client('rpcutil', :nodes => hosts) do |mco|
      result = mco.get_fact(:fact => fact)
      result.map do |resp|
        [resp[:sender], { fact.to_sym => resp[:data][:value] }]
      end
    end
    fact_response
  end

  def merge_attributes_by_fqdn(source_hash, target_hash)
    source_hash.each do |fqdn, attr|
      target_hash[fqdn] = attr.merge(target_hash[fqdn])
    end
    target_hash
  end

  def get_libvirt_domains(mco, hv)
    domains = Hash[]
    domain_name = hv[:sender].gsub(/^[^.]*\.mgmt\./, "")
    (hv[:data][:active_domains] + hv[:data][:inactive_domains]).each do |d|
      mco.domaininfo(:domain => d).map do |di|
        domains[d + "." + domain_name] = di[:data] if di[:statusmsg] == "OK"
      end
    end
    domains
  end

  # audit_domains is not enabled by default, as it takes significant time to complete
  def audit_hosts(fabric, audit_domains = false)
    fail "Unable to audit hosts when Fabric is nil" if fabric.nil?
    hosts = discover_compute_nodes(fabric)
    fail "unable to find any compute nodes in fabric #{fabric}" if hosts.empty?

    response = mco_client("libvirt", :nodes => hosts) do |mco|
      mco.hvinfo.map do |hv|
        fail "all compute nodes must respond with a status code of 0 #{hv.pretty_inspect}" unless hv[:statuscode] == 0

        domains = audit_domains ? {} : get_libvirt_domains(mco, hv)

        [hv[:sender], hv[:data].merge(:domains => domains)]
      end
    end

    fail "not all compute nodes (#{hosts.join(', ')}) responded -- got responses from " \
      "(#{response.map { |x| x[0] }.join(', ')})" unless hosts.size == response.size

    response_hash = Hash[response]
    allocation_tag_fact_hash = Hash[get_fact('allocation_tag', hosts)]
    allocation_disabled_fact_hash = Hash[get_fact('allocation_disabled', hosts)]
    response_hash_1 = merge_attributes_by_fqdn(allocation_disabled_fact_hash, response_hash)
    response_hash = merge_attributes_by_fqdn(allocation_tag_fact_hash, response_hash_1)

    libvirt_response_hash = Hash[response_hash]

    response = mco_client("computenodestorage", :nodes => hosts) do |mco|
      result = mco.details
      result.map do |resp|
        fail "all compute nodes must respond with a status code of 0 #{resp.pretty_inspect}" \
          unless resp[:statuscode] == 0

        [resp[:sender], { :storage => resp[:data] }]
      end
    end

    fail "not all compute nodes (#{hosts.join(', ')}) responded -- got responses from " \
      "(#{response.map { |x| x[0] }.join(', ')})" unless hosts.size == response.size

    storage_response_hash = Hash[response]

    libvirt_response_hash.each { |fqdn, attr| libvirt_response_hash[fqdn] = attr.merge(storage_response_hash[fqdn]) }

    libvirt_response_hash
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
