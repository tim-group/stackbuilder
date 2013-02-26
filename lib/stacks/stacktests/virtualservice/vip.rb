shared_examples_for "vip" do |virtualservice|

  it "can connect to #{virtualservice.vip_fqdn} on port 8000" do
    data = mco_client("nettest",:nodes=>["st-nat-001.mgmt.st.net.local"]) do |mco|
      result = mco.connect(:fqdn=>virtualservice.vip_fqdn, :port=>"8000")[0]
      raise "error attempting to connect to vip #{virtualservice.vip_fqdn}" if result[:statuscode]!=0
      result[:data]
    end

    data[:connect].should eql("Connected")
  end

end
