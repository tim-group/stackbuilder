require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'

describe Stacks::DSL do
  before do
    extend Stacks::DSL
  end

  it 'can pass in virtual_router_id for the loadbalancers and nat boxes to the stack instantiation' do
    stack "fabric" do
      loadbalancer
      natserver
    end

    env "parent", :primary_site => "st", :secondary_site => "bs" do
      env "e1", :lb_virtual_router_id => 1,
                :nat_front_virtual_router_id => 40,
                :nat_prod_virtual_router_id => 41,
                :primary_site => "space" do
        instantiate_stack "fabric"
      end

      env "e2", :lb_virtual_router_id => 2,
                :nat_front_virtual_router_id => 42,
                :nat_prod_virtual_router_id => 43 do
        instantiate_stack "fabric"
      end
    end

    expect(find("e1-lb-001.mgmt.space.net.local").virtual_router_id).to eql(1)
    expect(find("e2-lb-001.mgmt.st.net.local").virtual_router_id).to eql(2)
    expect(find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:front]).to eql(40)
    expect(find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:front]).to eql(42)
    expect(find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:prod]).to eql(41)
    expect(find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:prod]).to eql(43)
  end

  it 'can generate a pair of loadbalancers' do
    stack "fabric" do
      loadbalancer
    end
    env "rah", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
    end
    expect(find("rah-lb-001.mgmt.st.net.local")).not_to be_nil
    expect(find("rah-lb-002.mgmt.st.net.local")).not_to be_nil
  end

  it 'generates load balancer enc data with persistent when enable_persistent is specified' do
    stack "loadbalancer" do
      loadbalancer
    end

    stack "sftp" do
      virtual_sftpserver "sftp" do
        enable_persistence '21'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "sftp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    enc = loadbalancer.to_enc
    expect(enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['type']).to eql('sftp')
    expect(enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['realservers']['blue']).to \
      eql(["st-sftp-001.st.net.local", "st-sftp-002.st.net.local"])
    expect(enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['persistent_ports']).to eql(['21'])
    expect(enc['role::loadbalancer']['virtual_router_id']).to eql(1)
  end

  it 'generates load balancer enc data with the correct warn_level based on fewest number of servers in a group' do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = %w(blue green)
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    expect(loadbalancer.to_enc['role::loadbalancer']).to eql("virtual_router_id" => 1,
                                                             "virtual_servers" => {
                                                               "st-twoapp-vip.st.net.local" => {
                                                                 "healthcheck_timeout" => 10,
                                                                 "realservers" => {
                                                                   "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"]
                                                                 },
                                                                 "env" => "st",
                                                                 "app" => nil,
                                                                 "monitor_warn" => 1 },
                                                               "st-oneapp-vip.st.net.local" => {
                                                                 "healthcheck_timeout" => 10,
                                                                 "realservers" => {
                                                                   "green" => ["st-oneapp-002.st.net.local"],
                                                                   "blue" => ["st-oneapp-001.st.net.local"]
                                                                 },
                                                                 "env" => "st",
                                                                 "app" => nil,
                                                                 "monitor_warn" => 0
                                                               }
                                                             }
                                                            )
  end

  it 'generates load balancer enc data with the a different healthcheck_timeout if specified' do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = %w(blue green)
        self.healthcheck_timeout = 999
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    expect(loadbalancer.to_enc['role::loadbalancer']).to eql("virtual_router_id" => 1,
                                                             "virtual_servers" => {
                                                               "st-twoapp-vip.st.net.local" => {
                                                                 "healthcheck_timeout" => 10,
                                                                 "realservers" => {
                                                                   "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"]
                                                                 },
                                                                 "env" => "st",
                                                                 "app" => nil,
                                                                 "monitor_warn" => 1
                                                               },
                                                               "st-oneapp-vip.st.net.local" => {
                                                                 "healthcheck_timeout" => 10,
                                                                 "realservers" => {
                                                                   "green" => ["st-oneapp-002.st.net.local"],
                                                                   "blue" => ["st-oneapp-001.st.net.local"]
                                                                 },
                                                                 "env" => "st",
                                                                 "app" => nil,
                                                                 "monitor_warn" => 0,
                                                                 "healthcheck_timeout" => 999
                                                               }
                                                             }
                                                            )
  end

  it 'round robins the groups foreach instance' do
    stack "blah" do
      virtual_appserver "appx" do
        self.instances = 4
        self.application = "JavaHttpRef"
        self.groups = %w(blue green)
      end
    end
    env "ci", :primary_site => "st" do
      instantiate_stack "blah"
    end

    expect(find("ci-appx-001.mgmt.st.net.local")).to be_in_group('blue')
    expect(find("ci-appx-002.mgmt.st.net.local")).to be_in_group('green')
    expect(find("ci-appx-003.mgmt.st.net.local")).to be_in_group('blue')
    expect(find("ci-appx-004.mgmt.st.net.local")).to be_in_group('green')
  end

  it 'generates app server configuration appropriately' do
    stack "blah" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    expect(server.to_enc['role::http_app']).to eql('application' => 'JavaHttpRef',
                                                   'group' => 'blue',
                                                   'cluster' => 'ci-appx',
                                                   'vip_fqdn' => 'ci-appx-vip.st.net.local',
                                                   'environment' => 'ci',
                                                   'port'        => '8000',
                                                   'dependencies' => {},
                                                   'application_dependant_instances' => [],
                                                   'participation_dependant_instances' => [])
  end

  it 'generates app servers that are not part of a virtual service' do
    stack "blah" do
      standalone_appserver "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    expect(server.to_enc['role::http_app']).to eql('application' => 'JavaHttpRef',
                                                   'group' => 'blue',
                                                   'cluster' => 'ci-appx',
                                                   'environment' => 'ci',
                                                   'port'        => '8000',
                                                   'dependencies' => {},
                                                   'application_dependant_instances' => [],
                                                   'participation_dependant_instances' => [])
  end

  it 'returns nil if asked for a machine that does not exist' do
    expect(find("no-exist")).to eql(nil)
  end

  it 'throws an error if we try and instantiate a stack that isnt defined' do
    expect do
      env "myold", :primary_site => "x", :secondary_site => "y" do
        instantiate_stack "no-exist"
      end
    end.to raise_error "no stack found 'no-exist'"
  end

  it 'can be converted to an array of machine_defs (actual machines)' do
    stack "mystack" do
      loadbalancer
      natserver
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    expect(find_environment("e1").flatten.map(&:name)).to include("e1-lb-001", "e1-lb-002", "e1-nat-001", "e1-nat-002")
  end

  it 'things that are part of virtual services are given availability groups' do
    stack "mystack" do
      virtual_appserver "x"
      virtual_proxyserver "px"
      virtual_sftpserver "sx"
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    expect(find("e1-x-001.mgmt.space.net.local").availability_group).to eql("e1-x")
    expect(find("e1-px-001.mgmt.space.net.local").availability_group).to eql("e1-px")
    expect(find("e1-sx-001.mgmt.space.net.local").availability_group).to eql("e1-sx")
  end

  it 'adds ehcache settings to the enc if enable_ehcache is set inside a virtual_appserver' do
    stack "mystack" do
      virtual_appserver "x" do
        enable_ehcache
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    expect(server.to_enc['role::http_app']['dependencies']['cache.peers']).to eql('["e1-x-002.space.net.local"]')
    expect(server.to_enc['role::http_app']['dependencies']['cache.enabled']).to eql('true')
    expect(server.to_enc['role::http_app']['dependencies']['cache.registryPort']).to eql('49000')
    expect(server.to_enc['role::http_app']['dependencies']['cache.remoteObjectPort']).to eql('49010')
  end

  it 'allows specification of additional classes that should be included on the host' do
    stack "mystack" do
      virtual_appserver "x" do
        include_class 'test::puppet::class'
        each_machine do |_machine|
          include_class 'test::puppet::class2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc.keys.include? 'test::puppet::class'
    server.to_enc.keys.include? 'test::puppet::class2'
  end

  it 'allows specification of aditional classes with additional parameters that should be included on the host' do
    stack "mystack" do
      virtual_appserver "x" do
        include_class 'test::puppet::class', 'test_key' => 'test_value'
        each_machine do |_machine|
          include_class 'test::puppet::class2', 'test_key2' => 'test_value2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    expect(server.to_enc['test::puppet::class']).to eql('test_key' => 'test_value')
    expect(server.to_enc['test::puppet::class2']).to eql('test_key2' => 'test_value2')
  end
end
