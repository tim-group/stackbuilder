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
    env "rah", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
    end
    find("rah-lb-001.mgmt.st.net.local").should_not be_nil
    find("rah-lb-002.mgmt.st.net.local").should_not be_nil
  end

  it 'generates load balancer enc data with persistent when enable_persistent is specified'  do
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
    loadbalancer.to_enc.should eql(
      { "role::loadbalancer" => { "virtual_servers" => { "st-sftp-vip.st.net.local" => { "type" => "sftp", "realservers" => { "blue" => ["st-sftp-001.st.net.local", "st-sftp-002.st.net.local"] }, "monitor_warn" => 0, "persistent_ports" => ['21'] } }, "virtual_router_id" => 1 } }
    )
  end

  it 'generates load balancer enc data with the correct warn_level based on fewest number of servers in a group'  do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = ['blue', 'green']
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.to_enc.should eql(
      { "role::loadbalancer" =>         { "virtual_router_id" => 1,
                                          "virtual_servers" =>         { "st-twoapp-vip.st.net.local" =>           { "healthcheck_timeout" => 10,
                                                                                                                     "realservers" =>             { "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"] },
                                                                                                                     "env" => "st",
                                                                                                                     "app" => nil,
                                                                                                                     "monitor_warn" => 1 },
                                                                         "st-oneapp-vip.st.net.local" =>             { "healthcheck_timeout" => 10,
                                                                                                                       "realservers" =>               { "green" => ["st-oneapp-002.st.net.local"],
                                                                                                                                                        "blue" => ["st-oneapp-001.st.net.local"] },
                                                                                                                       "env" => "st",
                                                                                                                       "app" => nil,
                                                                                                                       "monitor_warn" => 0
              }
        }
        }
    }
    )
  end

  it 'generates load balancer enc data with the a different healthcheck_timeout if specified'  do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = ['blue', 'green']
        self.healthcheck_timeout = 999
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.to_enc.should eql(
      { "role::loadbalancer" =>         { "virtual_router_id" => 1,
                                          "virtual_servers" =>         { "st-twoapp-vip.st.net.local" =>           { "healthcheck_timeout" => 10,
                                                                                                                     "realservers" =>             { "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"] },
                                                                                                                     "env" => "st",
                                                                                                                     "app" => nil,
                                                                                                                     "monitor_warn" => 1 },
                                                                         "st-oneapp-vip.st.net.local" =>             { "healthcheck_timeout" => 10,
                                                                                                                       "realservers" =>               { "green" => ["st-oneapp-002.st.net.local"],
                                                                                                                                                        "blue" => ["st-oneapp-001.st.net.local"] },
                                                                                                                       "env" => "st",
                                                                                                                       "app" => nil,
                                                                                                                       "monitor_warn" => 0,
                                                                                                                       "healthcheck_timeout" => 999
              }
        }
        }
    }
    )
  end

  it 'can generate the load balancer spec for a sub environment' do
    stack "fabric" do
      loadbalancer
      virtual_sftpserver 'sftp'
    end

    stack "proxystack" do
      virtual_proxyserver "myproxy" do
      end
    end

    stack "blah" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
        self.groups = ['blue', 'green']
      end
      virtual_appserver "app2x" do
        self.application = "MySuperCoolApp"
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      env "ci" do
        instantiate_stack "fabric"
        instantiate_stack "blah"
      end

      env "ci2" do
        instantiate_stack "blah"
        instantiate_stack "proxystack"
      end
    end

    st_loadbalancer = find("st-lb-001.mgmt.st.net.local")
    st_loadbalancer.to_enc.should eql(
      {
        'role::loadbalancer' => {
          'virtual_router_id' => 1,
          'virtual_servers' => {
            'ci2-appx-vip.st.net.local' => {
              # 'type'        => 'app',

              'env' => 'ci2',
              'app' => 'JavaHttpRef',
              'monitor_warn' => 0,
              'healthcheck_timeout' => 10,

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
              'monitor_warn' => 1,
              'healthcheck_timeout' => 10,

              'realservers' => {
                'blue' => [
                  'ci2-app2x-001.st.net.local',
                  'ci2-app2x-002.st.net.local'
                ]
              }
            },
            'ci2-myproxy-vip.st.net.local' => {
              'type'        => 'proxy',
              'ports' => [80, 443],
              'realservers' => {
                'blue' => [
                  'ci2-myproxy-001.st.net.local',
                  'ci2-myproxy-002.st.net.local'
                ]
              }
            },
            'st-sftp-vip.st.net.local' => {
              'type'        => 'sftp',
              'monitor_warn' => 0,
              'persistent_ports'  => [],
              'realservers' => {
                'blue' => [
                  'st-sftp-001.st.net.local',
                  'st-sftp-002.st.net.local'
                ]
              }
            }
          } } })

    ci_loadbalancer = find("ci-lb-001.mgmt.st.net.local")
    ci_loadbalancer.to_enc.should eql({
                                        'role::loadbalancer' => {
                                          'virtual_router_id' => 1,
                                          'virtual_servers' => {
                                            'ci-appx-vip.st.net.local' => {
                                              'healthcheck_timeout' => 10,
                                              'monitor_warn' => 0,
                                              'env' => 'ci',
                                              'app' => 'JavaHttpRef',
                                              'realservers' => {
                                                'blue' => [
                                                  'ci-appx-001.st.net.local'
                                                ],
                                                'green' => [
                                                  'ci-appx-002.st.net.local'
                                                ]
                                              }
                                            },
                                            'ci-app2x-vip.st.net.local' => {
                                              'healthcheck_timeout' => 10,
                                              'monitor_warn' => 1,
                                              'env' => 'ci',
                                              'app' => 'MySuperCoolApp',
                                              'realservers' => {
                                                'blue' => [
                                                  'ci-app2x-001.st.net.local',
                                                  'ci-app2x-002.st.net.local'
                                                ]
                                              }
                                            },
                                            'ci-sftp-vip.st.net.local' => {
                                              'type'        => 'sftp',
                                              'monitor_warn' => 0,
                                              'persistent_ports'  => [],
                                              'realservers' => {
                                                'blue' => [
                                                  'ci-sftp-001.st.net.local',
                                                  'ci-sftp-002.st.net.local'
                                                ]
                                              }
                                            }
                                          }
                                        }
                                      })
  end

  it 'round robins the groups foreach instance' do
    stack "blah" do
      virtual_appserver "appx" do
        self.instances = 4
        self.application = "JavaHttpRef"
        self.groups = ['blue', 'green']
      end
    end
    env "ci", :primary_site => "st" do
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
        self.application = "JavaHttpRef"
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    server.to_enc.should eql({
                               'role::http_app' => {
                                 'application' => 'JavaHttpRef',
                                 'group' => 'blue',
                                 'cluster' => 'ci-appx',
                                 'vip_fqdn' => 'ci-appx-vip.st.net.local',
                                 'environment' => 'ci',
                                 'port'        => '8000',
                                 'dependencies' => {},
                                 'dependant_instances' => []
                               } })
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
    server.to_enc.should eql({
                               'role::http_app' => {
                                 'application' => 'JavaHttpRef',
                                 'group' => 'blue',
                                 'cluster' => 'ci-appx',
                                 'environment' => 'ci',
                                 'port'        => '8000',
                                 'dependencies' => {},
                                 'dependant_instances' => []
                               } })
  end

  it 'returns nil if asked for a machine that does not exist' do
    find("no-exist").should eql(nil)
  end

  it 'can build elastics search clusters' do
    stack "es" do
      elasticsearch do
      end
    end

    env "eg", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "es"
    end

    eg_es = find("eg-elasticsearch-001.mgmt.st.net.local")
    eg_es.to_enc.should eql({ 'role::elasticsearch_node' => { "cluster_nodes" => ["eg-elasticsearch-002.st.net.local", "eg-elasticsearch-001.st.net.local"] } })
  end

  it 'configures NAT boxes to NAT incoming public IPs' do
    stack "frontexample" do
      natserver
      virtual_proxyserver 'withnat' do
        enable_nat
      end
      virtual_sftpserver 'sftp' do
        enable_nat
      end
      virtual_appserver 'withoutnat' do
      end
    end

    stack "example2" do
      natserver
      virtual_appserver 'blahnat' do
        enable_nat
        self.ports = [8008]
      end
    end

    stack "exampledefaultport" do
      natserver
      virtual_appserver 'defaultport' do
        enable_nat
      end
    end

    env "eg", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "frontexample"
      env "sub" do
        instantiate_stack "example2"
        instantiate_stack "exampledefaultport"
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
                'dest_port'  => '80',
                'tcp'        => 'true',
                'udp'        => 'false'
              },
              'eg-withnat-vip.front.st.net.local 443' => {
                'dest_host'  => 'eg-withnat-vip.st.net.local',
                'dest_port'  => '443',
                'tcp'        => 'true',
                'udp'        => 'false'
              },
              'eg-sftp-vip.front.st.net.local 21' => {
                'dest_host'  => 'eg-sftp-vip.st.net.local',
                'dest_port'  => '21',
                'tcp'        => 'true',
                'udp'        => 'false'
              },
              'eg-sftp-vip.front.st.net.local 22' => {
                'dest_host'  => 'eg-sftp-vip.st.net.local',
                'dest_port'  => '22',
                'tcp'        => 'true',
                'udp'        => 'false'
              },
              'eg-sftp-vip.front.st.net.local 2222' => {
                'dest_host'  => 'eg-sftp-vip.st.net.local',
                'dest_port'  => '2222',
                'tcp'        => 'true',
                'udp'        => 'false'
              }
            }
          },
          'prod_virtual_router_id'  => 106,
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
              'sub-blahnat-vip.front.st.net.local 8008' => {
                'dest_host'  => 'sub-blahnat-vip.st.net.local',
                'dest_port'  => '8008',
                "tcp" => "true",
                "udp" => "false"
              },
              "sub-defaultport-vip.front.st.net.local 8000" => {
                "dest_port" => "8000",
                "dest_host" => "sub-defaultport-vip.st.net.local",
                "tcp" => "true",
                "udp" => "false"
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
      env "myold", :primary_site => "x", :secondary_site => "y" do
        instantiate_stack "no-exist"
      end
    }.to raise_error "no stack found 'no-exist'"
  end

  it 'generates proxyserver enc data' do
    stack "ref" do
      virtual_appserver "refapp" do
        self.application = "MyApp"
      end

      virtual_appserver "ref2app" do
        self.application = "MyOtherApp"
      end

      virtual_appserver "downstreamapp" do
      end

      virtual_proxyserver "refproxy" do
        vhost("refapp") do
          with_alias "example.timgroup.com"
          with_redirect "old-example.timgroup.com"
        end
        vhost("ref2app") do
          pass "/resources" => "downstreamapp"
        end
      end
    end

    env "env", :primary_site => "st", "refproxy.vhost.ref2app.server_name" => "example.timgroup.com" do
      instantiate_stack "ref"
    end

    proxyserver = find("env-refproxy-001.mgmt.st.net.local")

    proxyserver.to_enc.should eql(
      {
        'role::proxyserver' => {
          'default_ssl_cert' => 'wildcard_timgroup_com',
          'prod_vip_fqdn' => 'env-refproxy-vip.st.net.local',
          'environment' => 'env',
          'vhosts'        => {
            'env-refproxy-vip.front.st.net.local' => {
              'application'    => 'MyApp',
              'proxy_pass_rules'  => {
                '/' => "http://env-refapp-vip.st.net.local:8000"
              },
              'redirects'      => ['old-example.timgroup.com'],
              'aliases'        => ['example.timgroup.com', 'env-refproxy-vip.st.net.local'],
              'type' => 'default',
              'vhost_properties' => {},
              'cert' => 'wildcard_timgroup_com'
            },
            'example.timgroup.com' => {
              'application'    => 'MyOtherApp',
              'proxy_pass_rules'  => {
                '/' => "http://env-ref2app-vip.st.net.local:8000",
                '/resources' => "http://env-downstreamapp-vip.st.net.local:8000"
              },
              'redirects'      => [],
              'aliases'        => ['env-refproxy-vip.front.st.net.local', 'env-refproxy-vip.st.net.local'],
              'type' => 'default',
              'vhost_properties' => {},
              'cert' => 'wildcard_timgroup_com'
            }
          }
        }
      }
    )
  end

  it 'generates proxy server enc data with persistent when enable_persistent is specified'  do
    stack "loadbalancer" do
      loadbalancer
    end

    stack "proxyserver" do
      virtual_proxyserver "proxy" do
        enable_persistence '443'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.to_enc.should eql(
      {
        "role::loadbalancer" => {
          "virtual_router_id" => 1,
          "virtual_servers" => {
            "st-proxy-vip.st.net.local" =>
            {
              "type" => "proxy",
              "ports" => [80, 443],
              "realservers" => {
                "blue" => [
                  "st-proxy-001.st.net.local",
                  "st-proxy-002.st.net.local"
                ]
              },
              "persistent_ports" => ["443"]
            }
          }
        }
      }
    )
  end

  it 'can generate the correct enc data for sftp servers' do
    stack "fabric" do
      virtual_sftpserver 'sftp' do
      end
    end

    env "rah", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
    end

    find("rah-sftp-001.mgmt.st.net.local").should_not be_nil
    find("rah-sftp-002.mgmt.st.net.local").should_not be_nil

    find("rah-sftp-001.mgmt.st.net.local").to_enc.should eql(
      {
        'role::sftpserver' => {
          'vip_fqdn' => 'rah-sftp-vip.st.net.local',
          'env' => 'rah'
        }
      }
    )

    find("rah-sftp-002.mgmt.st.net.local").to_enc.should eql(
      {
        'role::sftpserver' => {
          'vip_fqdn' => 'rah-sftp-vip.st.net.local',
          'env' => 'rah'
        }
      }
    )
  end

  it 'can be converted to an array of machine_defs (actual machines)' do
    stack "mystack" do
      loadbalancer
      natserver
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    find_environment("e1").flatten.map(&:name).should eql(["e1-lb-001", "e1-lb-002", "e1-nat-001", "e1-nat-002"])
  end

  it 'can build forward proxy servers' do
    stack "mystack" do
      rate_limited_forward_proxy 's3proxy'
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    find("e1-s3proxy-001.mgmt.space.net.local").to_enc.should eql({
                                                                    'role::rate_limited_forward_proxy' => {}
                                                                  })

    find("e1-s3proxy-001.mgmt.space.net.local").networks.should eql([:mgmt, :prod])
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

    find_environment("e1")["mystack"]["x"]["x-001"].availability_group.should eql("e1-x")
    find_environment("e1")["mystack"]["px"]["px-001"].availability_group.should eql("e1-px")
    find_environment("e1")["mystack"]["sx"]["sx-001"].availability_group.should eql("e1-sx")
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
    server.to_enc['role::http_app']['dependencies']['cache.peers'].should eql('["e1-x-002.space.net.local"]')
    server.to_enc['role::http_app']['dependencies']['cache.enabled'].should eql('true')
    server.to_enc['role::http_app']['dependencies']['cache.registryPort'].should eql('49000')
    server.to_enc['role::http_app']['dependencies']['cache.remoteObjectPort'].should eql('49010')
  end

  it 'allows specification of aditional hosts that are allowed to talk to the app or service' do
    stack "mystack" do
      virtual_appserver "x" do
        allow_host '1.1.1.1'
        each_machine do |machine|
          allow_host '2.2.2.2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc['role::http_app']['allowed_hosts'].should eql(['1.1.1.1', '2.2.2.2'])
  end

  it 'allows specification of additional classes that should be included on the host' do
    stack "mystack" do
      virtual_appserver "x" do
        include_class 'test::puppet::class'
        each_machine do |machine|
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
        each_machine do |machine|
          include_class 'test::puppet::class2', 'test_key2' => 'test_value2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc['test::puppet::class'].should eql({ 'test_key' => 'test_value' })
    server.to_enc['test::puppet::class2'].should eql({ 'test_key2' => 'test_value2' })
  end
end
