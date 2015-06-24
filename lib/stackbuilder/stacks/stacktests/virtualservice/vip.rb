require 'facter'
require 'logger'
require "net/https"
require "net/http"
require "uri"

shared_examples_for "vip" do |virtualservice|
  virtualservice.ports do |port|
    it "can connect to #{virtualservice.vip_fqdn(:prod, :primary_site)} ... on #{port}" do
      if (virtualservice.fabric == "local")
        node_to_execute_from = Facter["fqdn"].value
      else
        node_to_execute_from = "#{virtualservice.environment.name}-lb-001.mgmt.#{virtualservice.fabric}.net.local"
      end
      vip_fqdn = virtualservice.vip_fqdn(:prod, :primary_site)
      logger.debug("executing vip test for #{vip_fqdn} test on #{node_to_execute_from}")

      data = mco_client("nettest", :nodes => [node_to_execute_from]) do |mco|
        result = mco.connect(:fqdn => vip_fqdn, :port => "#{port}")[0]
        fail "error attempting to connect to vip #{vip_fqdn}" if result[:statuscode] != 0
        result[:data]
      end
      data[:connect].should eql("Connected")
    end
  end

  it 'check there are N instances in the load balancer' do
    pending("not implemented yet")
  end

  if virtualservice.nat
    it "#{virtualservice.vip_fqdn(:front, :primary_site)} can be accessed from the Internetover http" do
      pending("nat boxes need to be auto-built")
      uri = URI.parse("http://#{virtualservice.vip_fqdn(:front, :primary_site)}")
      response = Net::HTTP.get_response(uri)
      response.code.should eql('302')
    end

    it "#{virtualservice.vip_fqdn(:front, :primary_site)} can be accessed from the Internet over https" do
      pending("nat boxes need to be auto-built")
      request_url = "https://#{virtualservice.vip_fqdn(:front, :primary_site)}"

      uri = URI.parse(request_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(request_url)

      response = http.start { |h| h.request(request) }
      response.code.should eql('200')
    end
  end
end
