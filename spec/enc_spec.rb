require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'
require 'matchers/server_matcher'

describe Stacks::DSL do

  before do
    extend Stacks::DSL
    class Resolv::DNS
      def getaddress(url)
        return "1.1.1.1"
      end
    end
  end

  it 'can pass in virtual_router_id for the loadbalancers and nat boxes to the stack instantiation' do
    stack "fabric" do
      loadbalancer
      natserver
    end

    env "parent", :primary_site=>"st", :secondary_site=>"bs" do
      env "e1", :lb_virtual_router_id=>1,
                :nat_front_virtual_router_id=>40,
                :nat_prod_virtual_router_id=>41,
                :primary_site=>"space" do
        instantiate_stack "fabric"
      end

      env "e2", :lb_virtual_router_id=>2,
                :nat_front_virtual_router_id=>42,
                :nat_prod_virtual_router_id=>43 do
        instantiate_stack "fabric"
      end
    end

    find("e1-lb-001.mgmt.space.net.local").virtual_router_id.should eql(1)
    find("e2-lb-001.mgmt.st.net.local").virtual_router_id.should eql(2)
    find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:front].should eql(40)
    find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:front].should eql(42)
    find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:prod].should eql(41)
    find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:prod].should eql(43)
  end

  it 'can generate a pair of loadbalancers' do
    stack "fabric" do
      loadbalancer
    end
    env "rah", :primary_site=>"st", :secondary_site=>"bs" do
      instantiate_stack "fabric"
    end
    find("rah-lb-001.mgmt.st.net.local").should_not be_nil
    find("rah-lb-002.mgmt.st.net.local").should_not be_nil
  end

  it 'generates load balancer enc data for a sub environment' do
    stack "fabric" do
      loadbalancer
    end

    stack "blah" do
      virtual_appserver "appx"
      virtual_appserver "app2x"
    end

    env "st", :primary_site=>"st", :secondary_site=>"bs" do
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
      virtual_appserver "appx" do
        self.application="JavaHttpRef"
        self.groups = ['blue','green']
      end
      virtual_appserver "app2x" do
        self.application="MySuperCoolApp"
      end
    end

    env "st", :primary_site=>"st", :secondary_site=>"bs" do
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
       'role::loadbalancer' => {
      'virtual_router_id' => 1,
      'virtual_servers' => {
      'ci2-appx-vip.st.net.local' => {
      'env' => 'ci2',
      'app' => 'JavaHttpRef',
      'realservers' => {
      'blue' => [
        'ci2-appx-001.st.net.local'
    ],
      'green' => [
        'ci2-appx-002.st.net.local'
    ]
    }
    },
      'ci2-app2x-vip.st.net.local' => {
      'env' => 'ci2',
      'app' => 'MySuperCoolApp',
      'realservers' => {
      'blue' => [
        'ci2-app2x-001.st.net.local',
        'ci2-app2x-002.st.net.local'
    ]
    }
    }}}}
    )

    ci_loadbalancer = find("ci-lb-001.mgmt.st.net.local")
    ci_loadbalancer.virtual_services.size.should eql(2)
    ci_loadbalancer.to_enc.should eql(
      {
      'role::loadbalancer' =>
      {
       'virtual_router_id' => 1,
       'virtual_servers' => {
        'ci-appx-vip.st.net.local' => {
        'env' => 'ci',
        'app' => 'JavaHttpRef',
        'realservers' => {
        'blue' => [
          'ci-appx-001.st.net.local'],
          'green'=> [
            'ci-appx-002.st.net.local']
      }},
        'ci-app2x-vip.st.net.local' => {
        'env' => 'ci',
        'app' => 'MySuperCoolApp',
        'realservers' => {
        'blue' => [
          'ci-app2x-001.st.net.local',
          'ci-app2x-002.st.net.local'
      ]}}}}}
    )
  end

  it 'round robins the groups foreach instance' do
    stack "blah" do
      virtual_appserver "appx" do
        self.instances=4
        self.application="JavaHttpRef"
        self.groups=['blue', 'green']
      end
    end
    env "ci", :primary_site=>"st" do
      instantiate_stack "blah"
    end

    find("ci-appx-001.mgmt.st.net.local").should be_in_group('blue')
    find("ci-appx-002.mgmt.st.net.local").should be_in_group('green')
    find("ci-appx-003.mgmt.st.net.local").should be_in_group('blue')
    find("ci-appx-004.mgmt.st.net.local").should be_in_group('green')
  end

  it 'generates app server configuration appropriately' do
    stack "blah" do
      virtual_appserver "appx" do
        self.application="JavaHttpRef"
      end
    end

    env "ci", :primary_site=>"st", :secondary_site=>"bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    server.to_enc.should eql({
      'role::http_app'=> {
      'application' => 'JavaHttpRef',
      'group' => 'blue',
      'vip' => '1.1.1.1',
      'environment' => 'ci'
    }})
  end

  it 'returns nil if asked for a machine that does not exist' do
    find("no-exist").should eql(nil)
  end

  it 'configures NAT boxes to NAT incoming public IPs' do
    stack "frontexample" do
      natserver
      virtual_appserver 'withnat' do
        enable_nat
      end
      virtual_appserver 'withoutnat' do
      end
    end

    stack "example2" do
      natserver
      virtual_appserver 'blahnat' do
        enable_nat
        self.port=8008
      end
    end

    env "eg", :primary_site=>"st", :secondary_site=>"bs" do
      instantiate_stack "frontexample"
      env "sub" do
        instantiate_stack "example2"
      end
    end

    eg_nat = find("eg-nat-001.mgmt.st.net.local")
    eg_nat.to_enc.should eql(
      {
        'role::natserver' => {
          'rules' => {
            'SNAT' => {
              'prod' => {
                'to_source' => 'nat-vip.front.st.net.local'
              }
            },
            'DNAT' => {
              'eg-withnat-vip.front.st.net.local 80' => {
                'dest_host'  => 'eg-withnat-vip.st.net.local',
                'dest_port'  => '8000'
              }
            }
          },
          'prod_virtual_router_id' => 106,
          'front_virtual_router_id' => 105
        }
      }
    )

    sub_nat = find("sub-nat-001.mgmt.st.net.local")
    sub_nat.to_enc.should eql(
      {
        'role::natserver' => {
          'rules' => {
            'SNAT' => {
              'prod' => {
                'to_source' => 'nat-vip.front.st.net.local'
              }
            },
            'DNAT' => {
              'sub-blahnat-vip.front.st.net.local 80' => {
                'dest_host'  => 'sub-blahnat-vip.st.net.local',
                'dest_port'  => '8008'
              }
            }
          },
          'prod_virtual_router_id' => 106,
          'front_virtual_router_id' => 105
        }
      }
    )
  end

  it 'throws an error if we try and instantiate a stack that isnt defined' do
    expect {
      env "myold", :primary_site=>"x", :secondary_site=>"y" do
      instantiate_stack "no-exist"
      end
    }.to raise_error "no stack found 'no-exist'"
  end


  it 'generates proxyserver enc data' do
    pending("implementation")

    stack "ref" do
      virtual_appserver "refapp"
      virtual_proxyserver "refproxy" do
        vhost("refapp") do
          add_alias "example.timgroup.com"
        end
      end
    end


    env "env", :primary_site=>"st" do
      instantiate_stack "ref"
    end

    proxyserver.to_enc.should eql(
      {'role::proxyserver' => {
          'prod_vip_fqdn' => 'env-refproxy-vip.st.net.local',
          'vhosts'        => {
            'example.timgroup.com' => {
              'application'    => 'ref',
              'proxy_pass_to'  => "http://env-refapp-vip.st.net.local:8000",
              'redirects'      => ['old-example.timgroup.com'],
              'aliases'        => ['env-refproxy-vip.front.st.net.local'],
            }
          }
        }
      }
    )
  end

end
