require 'facter'
require 'logger'

shared_examples_for "vip" do |virtualservice|

  it "can connect to #{virtualservice.vip_fqdn} on port 8000" do
    if (virtualservice.fabric == "local")
      node_to_execute_from = Facter["fqdn"].value()
    else
      node_to_execute_from = "#{virtualservice.environment.name}-lb-001.mgmt.#{virtualservice.fabric}.net.local"
    end

    logger.debug("executing vip test for #{virtualservice.vip_fqdn} test on #{node_to_execute_from}")

    data = mco_client("nettest",:nodes=>[node_to_execute_from]) do |mco|
      result = mco.connect(:fqdn=>virtualservice.vip_fqdn, :port=>"8000")[0]
      raise "error attempting to connect to vip #{virtualservice.vip_fqdn}" if result[:statuscode]!=0
      result[:data]
    end
    data[:connect].should eql("Connected")
  end

end
