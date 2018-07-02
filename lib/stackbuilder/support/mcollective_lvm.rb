require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveLvm
  include Support::MCollective

  def logical_volumes(host_fqdn)
    host_volumes = mco_client("lvm", :nodes => [host_fqdn]) do |mco|
      mco.lvs.map do |lvs|
        fail "failed to get logical volume info for #{host_fqdn}: #{lvs[:statusmsg]}" if lvs[:statuscode] != 0
        lvs[:data][:lvs]
      end
    end
    fail "Got no response from mcollective lvs.lvm request to #{host_fqdn}" if host_volumes.empty?
    host_volumes[0]
  end
end
