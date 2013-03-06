require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'

describe Stacks::DSL do

  before do
    extend Stacks::DSL
  end

  it 'generates config for a sub environment' do
    stack "fabric" do
      loadbalancer
    end

    stack "blah" do
      virtualservice "appx"
      virtualservice "app2x"
    end

    env "st", :primary=>"st", :secondary=>"bs" do
      instantiate_stack "fabric"
      env "ci" do
        instantiate_stack "fabric"
        instantiate_stack "blah"
      end
    end

    loadbalancer = find("ci-lb-001.mgmt.st.net.local")
    loadbalancer.virtual_services.size.should eql(2)
  end

  it 'can generate the load balancer spec for a sub environment' do
    stack "fabric" do
      loadbalancer
    end

    stack "blah" do
      virtualservice "appx"
      virtualservice "app2x"
    end

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

    st_loadbalancer = find("st-lb-001.mgmt.st.net.local")
    st_loadbalancer.virtual_services.size.should eql(2)
    st_loadbalancer.to_enc.should eql(
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

    ci_loadbalancer = find("ci-lb-001.mgmt.st.net.local")
    ci_loadbalancer.virtual_services.size.should eql(2)
    ci_loadbalancer.to_enc.should eql(
      {
      'role::loadbalancer' =>
      {
        'virtual_servers' => {
        'ci-appx-vip.st.net.local' => {
        'env' => 'ci',
        'app' => 'JavaHttpRef',
        'realservers' => {
        'blue' => [
          'ci-appx-001.st.net.local',
          'ci-appx-002.st.net.local'
      ]}},
        'ci-app2x-vip.st.net.local' => {
        'env' => 'ci',
        'app' => 'JavaHttpRef',
        'realservers' => {
        'blue' => [
          'ci-app2x-001.st.net.local',
          'ci-app2x-002.st.net.local'
      ]}}}}}
    )
  end

  it 'generates app server configuration appropriately' do
    stack "blah" do
      virtualservice "appx"
    end

    env "ci", :primary=>"st", :secondary=>"bs" do
      instantiate_stack "blah"
    end

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

  it 'configures NAT boxes to NAT incoming public IPs' do
    stack "frontexample" do
      natserver
      virtualservice 'withnat' do
        enable_nat
      end
      virtualservice 'withoutnat' do
      end
    end

    env "eg", :primary=>"st", :secondary=>"bs" do
      instantiate_stack "frontexample"
    end

    nat = find("eg-nat-001.mgmt.st.net.local")
    nat.to_enc.should eql(
      {
      'role::natserver' => {
      'rules' => [
        {
      'from' => 'eg-withnat-vip.front.st.net.local',
      'to'  => 'eg-withnat-vip.st.net.local'
    }]
    }})
  end

  it 'throws an error if we try and instantiate a stack that isnt defined' do

    expect {
      env "myold", :primary=>"x", :secondary=>"y" do
        instantiate_stack "no-exist"
      end
    }.to raise_error "no stack found 'no-exist'"
  end
end
