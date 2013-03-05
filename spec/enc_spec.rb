require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'

describe Stacks::DSL do

  before do
    extend Stacks::DSL
    stack "fabric" do
      loadbalancer
    end

    stack "blah" do
      virtualservice "appx"
      virtualservice "app2x"
    end

    env "ci", :primary=>"st", :secondary=>"bs"

    env "st", :primary=>"st", :secondary=>"bs" do
      instantiate_stack "fabric"
      env "ci" do
        instantiate_stack "fabric"
        instantiate_stack "blah"
      end
      env "ci2" do
        instantiate_stack "blah"
      end
    end
    env "bla", :primary=>"st", :secondary=>"bs"
  end

  it 'generates config for a sub environment' do
    loadbalancer = find("ci-lb-001.mgmt.st.net.local")
    loadbalancer.virtual_services.size.should eql(2)
  end

  it 'can generate the load balancer spec' do
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.virtual_services.size.should eql(2)
    loadbalancer.to_enc.should eql(
      {
      'role::loadbalancer' =>
      {
        'virtual_servers' => {
        'ci2-appx-vip.st.net.local' => {
        'env' => 'ci2',
        'app' => 'JavaHttpRef',
        'realservers' => {
        'blue' => [
          'ci2-appx-001.st.net.local',
          'ci2-appx-002.st.net.local'
      ]}},
        'ci2-app2x-vip.st.net.local' => {
        'env' => 'ci2',
        'app' => 'JavaHttpRef',
        'realservers' => {
        'blue' => [
          'ci2-app2x-001.st.net.local',
          'ci2-app2x-002.st.net.local'
      ]}}}}}
    )
  end

  it 'generates app server configuration appropriately' do
    class Resolv::DNS
      def getaddress(url)
        return "1.1.1.1"
      end
    end

    server = find("ci-appx-001.mgmt.st.net.local")

    server.to_enc.should eql({
      'role::http_app'=> {
      'application' => 'appx',
      'groups' => ['blue'],
      'vip' => '1.1.1.1',
      'environment' => 'ci'
    }})
  end

  it 'returns nil if asked for a machine that does not exist' do
    class Resolv::DNS
      def getaddress(url)
        return "1.1.1.1"
      end
    end

    find("no-exist").should eql(nil)
  end

end
