require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveNettest
  include Support::MCollective

  def test_connection(host_fqdn, vip_fqdn, vip_port)
    results = mco_client("nettest", :nodes => [host_fqdn]) do |mco|
      mco.connect(:fqdn => vip_fqdn, :port => "#{vip_port}").map do |conn|
        fail "failed to get logical volume info for #{host_fqdn}: #{conn[:statusmsg]}" if conn[:statuscode] != 0
        conn[:data][:connect]
      end
    end
    fail "Got no response from mcollective nettest.connect request to #{host_fqdn}" if results.empty?
    results[0]
  end
end
