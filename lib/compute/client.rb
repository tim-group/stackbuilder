require 'compute/namespace'
require 'mcollective'
require 'support/mcollective'

class Compute::Client
  include Support::MCollective

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

    Hash[response]
  end

  def find_hosts(fabric)
    mco_client("computenode", :fabric => fabric) do |mco|
      mco.discover.sort()
    end
  end

  def invoke(selector, specs, client_options)
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
    invoke :launch, specs, :timeout => 1000, :nodes => [host]
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

