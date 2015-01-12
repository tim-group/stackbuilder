require 'compute/namespace'
require 'mcollective'
require 'support/mcollective'

class Compute::Client
  include Support::MCollective

  def get_fact(fact, hosts)
    fact_response = mco_client('rpcutil',:nodes=>hosts) do |mco|
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


  def audit_hosts(fabric)
    hosts = find_hosts(fabric)

    raise "unable to find any compute nodes" if hosts.empty?

    response = mco_client("libvirt", :nodes=>hosts) do |mco|
      result = mco.hvinfo()
      result.map do |hv|
        raise "all compute nodes must respond with a status code of 0 #{hv.pretty_inspect}" unless hv[:statuscode]==0
        [hv[:sender], hv[:data]]
      end
    end

    raise "not all compute nodes (#{hosts.join(', ')}) responded -- got responses from (#{response.map do |x| x[0] end.join(', ')})" unless hosts.size == response.size

    response_hash = Hash[response]
    allocation_disabled_fact_hash = Hash[get_fact('allocation_disabled', hosts)]
    response_hash = merge_attributes_by_fqdn(allocation_disabled_fact_hash, response_hash)

    libvirt_response_hash = Hash[response_hash]

    # FIXME:
    # Once all computenodes have new storage config, unwrap this code
    # from begin/rescue
    response = nil
    begin
      response = mco_client("computenodestorage", :nodes => hosts) do |mco|
        result = mco.details()
        result.map do |resp|
          # FIXME: Once all compute nodes have new storage config, renable this
          #raise "all compute nodes must respond with a status code of 0 #{resp.pretty_inspect}" unless resp[:statuscode]==0
          [resp[:sender], {:storage => resp[:data]}]
        end
      end

      raise "not all compute nodes (#{hosts.join(', ')}) responded -- got responses from (#{response.map do |x| x[0] end.join(', ')})" unless hosts.size == response.size
    rescue
    end


    # FIXME:
    # Once all computenodes have new storage config, unwrap this code
    # from unless
    unless response.nil?
      storage_response_hash = Hash[response]

      libvirt_response_hash.each do |fqdn, attr|
        libvirt_response_hash[fqdn] = attr.merge(storage_response_hash[fqdn])
      end
    end

    libvirt_response_hash


  end

  def find_hosts(fabric)
    mco_client("computenode", :fabric => fabric) do |mco|
      mco.discover.sort()
    end
  end

  def invoke(selector, specs, client_options)
    # debug information / bkhidhir / 2015-01-12
    puts selector
    puts specs
    puts client_options

    mco_client("computenode", client_options) do |mco|
      mco.send(selector, :specs => specs).map do |node|
        if node[:statuscode] != 0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def launch(host, specs)
    invoke :launch, specs, :timeout => 10000, :nodes => [host]
  end

  def allocate_ips(host, specs)
    invoke :allocate_ips, specs, :nodes => [host]
  end

  def free_ips(host, specs)
    invoke :free_ips, specs, :nodes => [host]
  end

  def clean(fabric, specs)
    invoke :clean, specs, :fabric => fabric
  end

  def add_cnames(host, spec)
    invoke :add_cnames, spec, :nodes => [host]
  end

  def remove_cnames(host, spec)
    invoke :remove_cnames, spec,:nodes => [host]
  end
end

