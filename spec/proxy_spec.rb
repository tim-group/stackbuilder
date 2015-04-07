require 'stacks/test_framework'

describe_stack 'exampleproxy' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        vhost('exampleapp') do
        end
        vhost('exampleapp2', 'example.overridden') do
        end
        enable_nat
        self.ports = [80, 443, 8443]
      end

      virtual_appserver 'exampleapp' do
        self.groups = ['blue']
        self.application = 'example'
      end

      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "exampleproxy"
    end
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql("role::proxyserver" => {
                             "default_ssl_cert" => 'wildcard_timgroup_com',
                             "environment" => "e1",
                             "vhosts" => {
                               "e1-exampleproxy-vip.front.space.net.local" => {
                                 "proxy_pass_rules" => {
                                   "/" => "http://e1-exampleapp-vip.space.net.local:8000"
                                 },
                                 "aliases" => ["e1-exampleproxy-vip.space.net.local"],
                                 "application" => "example",
                                 "redirects" => [],
                                 "type" => "default",
                                 "vhost_properties" => {},
                                 "cert" => 'wildcard_timgroup_com'

                               },
                               "example.overridden" => {
                                 "proxy_pass_rules" => {
                                   "/" => "http://e1-exampleapp2-vip.space.net.local:8000"
                                 },
                                 "aliases" => [
                                   "e1-exampleproxy-vip.front.space.net.local",
                                   "e1-exampleproxy-vip.space.net.local"
                                 ],
                                 "application" => "example",
                                 "redirects" => [],
                                 "type" => "default",
                                 "vhost_properties" => {},
                                 "cert" => 'wildcard_timgroup_com'
                               }
                             },
                             "prod_vip_fqdn" => "e1-exampleproxy-vip.space.net.local",
                             "environment" => "e1"
                           })
  end
end

describe_stack 'proxy servers can have the default ssl cert and vhost ssl certs overriden' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        @cert = 'test_cert_change'
        vhost('exampleapp') do
          @cert = 'test_vhost_cert_change'
        end
      end

      virtual_appserver 'exampleapp' do
        self.groups = ['blue']
        self.application = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "exampleproxy"
    end
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    enc['role::proxyserver']['default_ssl_cert'].should eql('test_cert_change')
    enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['cert'].
      should eql('test_vhost_cert_change')
  end
end

describe_stack 'proxy pass rules without an environment default to the environment set (if any) of the vhost' do
  given do
    stack 'funds_proxy' do
      virtual_proxyserver 'fundsproxy' do
        @cert = 'wildcard_youdevise_com'
        vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'mirror') do
          @cert = 'wildcard_timgroup_com'
          add_properties 'is_hip' => true
          add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'mirror'
          add_pass_rule "/HIP/blah", :service => "blondinapp", :environment => 'latest'
          add_pass_rule "/HIP/blah2", :service => "blondinapp", :environment => 'shared'
          add_pass_rule "/HIP/blah3", :service => "blondinapp"
        end
        enable_nat
      end
    end
    stack 'funds' do
      virtual_appserver 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
      end

      virtual_appserver 'fundsuserapp' do
        self.groups = ['blue']
        self.application = 'tfunds'
        self.ports = [8443]
      end
    end
    env 'shared', :primary_site => 'oy' do
      instantiate_stack 'funds_proxy'
      instantiate_stack 'funds'

      env 'mirror' do
        instantiate_stack 'funds'
      end
      env 'latest' do
        instantiate_stack 'funds'
      end
    end
  end
  host('shared-fundsproxy-001.mgmt.oy.net.local') do |host|
    host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']['/'].
      should eql 'http://mirror-fundsuserapp-vip.oy.net.local:8000'
    host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']['/HIP/resources'].
      should eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
    host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']['/HIP/blah'].
      should eql 'http://latest-blondinapp-vip.oy.net.local:8000'
    host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']['/HIP/blah2'].
      should eql 'http://shared-blondinapp-vip.oy.net.local:8000'
    host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']['/HIP/blah3'].
      should eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
  end
end
