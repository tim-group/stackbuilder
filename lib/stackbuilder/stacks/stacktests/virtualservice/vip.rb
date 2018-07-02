require 'logger'
require 'stackbuilder/support/mcollective_nettest'

shared_examples_for 'vip' do |virtual_service|
  virtual_service.ports do |port|
    it "can connect to #{virtual_service.vip_fqdn(:prod, :primary_site)} ... on #{port}" do
      if virtual_service.fabric == 'local'
        require 'facter'
        node_to_execute_from = Facter['fqdn'].value
      else
        node_to_execute_from = "#{virtual_service.environment.name}-lb-001.mgmt.#{virtual_service.fabric}.net.local"
      end
      vip_fqdn = virtual_service.vip_fqdn(:prod, :primary_site)
      logger.debug("executing vip test for #{vip_fqdn} test on #{node_to_execute_from}")

      mco_nettest = Support::MCollectiveNettest.new
      result = mco_nettest.test_connection(node_to_execute_from, vip_fqdn, port)
      result.should eql('Connected')
    end
  end
end
