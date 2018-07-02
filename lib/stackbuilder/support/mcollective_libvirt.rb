require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveLibvirt
  include Support::MCollective

  def hvinfo(host_fqdns)
    libvirt_response = Hash[mco_client("libvirt", :nodes => host_fqdns) do |mco|
      mco.hvinfo.map do |hv|
        fail "all compute nodes must respond with a status code of 0 #{hv.pretty_inspect}" unless hv[:statuscode] == 0
        [hv[:sender], hv[:data]]
      end
    end]

    missing_hosts = host_fqdns - libvirt_response.keys
    fail "libvirt - not all compute nodes responded -- missing responses from (#{missing_hosts.join(', ')})" unless missing_hosts.empty?

    libvirt_response
  end

  def domaininfo(host_fqdn, vm_names)
    mco_client("libvirt", :timeout => 1, :nodes => [host_fqdn]) do |mco|
      Hash[vm_names.map { |vm_name| [vm_name, get_vm_info(mco, vm_name)] }]
    end
  end

  private

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
