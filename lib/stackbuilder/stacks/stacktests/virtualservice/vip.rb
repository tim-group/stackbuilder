require 'facter'
require 'logger'
require 'net/https'
require 'net/http'
require 'uri'

shared_examples_for 'vip' do |virtualservice|
  virtualservice.ports do |port|
    it "can connect to #{virtualservice.vip_fqdn(:prod, :primary_site)} ... on #{port}" do
      if (virtualservice.fabric == 'local')
        node_to_execute_from = Facter['fqdn'].value
      else
        node_to_execute_from = "#{virtualservice.environment.name}-lb-001.mgmt.#{virtualservice.fabric}.net.local"
      end
      vip_fqdn = virtualservice.vip_fqdn(:prod, :primary_site)
      logger.debug("executing vip test for #{vip_fqdn} test on #{node_to_execute_from}")

      data = mco_client('nettest', :nodes => [node_to_execute_from]) do |mco|
        result = mco.connect(:fqdn => vip_fqdn, :port => "#{port}")[0]
        fail "error attempting to connect to vip #{vip_fqdn}" if result[:statuscode] != 0
        result[:data]
      end
      data[:connect].should eql('Connected')
    end
  end
end
