require 'stacks/test_framework'

describe_stack 'exampleproxy' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        vhost('exampleapp') do
        end
        sso_vhost('exampleapp') do
        end
        vhost('exampleapp2') do
        end
        sso_vhost('exampleapp2') do
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

    env "e1", :primary_site => "space",
      'exampleproxy.vhost.exampleapp2.server_name' => 'example.overridden',
      'exampleproxy.vhost.exampleapp2-sso.server_name' => 'example-sso.overridden' do
        instantiate_stack "exampleproxy"
      end
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      "role::proxyserver" => {
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
            "cert" => 'wildcard_timgroup_com',

          },
          "e1-exampleproxy-sso-vip.front.space.net.local" => {
            "proxy_pass_rules" => {
              "/" => "http://e1-exampleapp-vip.space.net.local:8000"
            },
            "aliases" => ["e1-exampleproxy-sso-vip.space.net.local"],
            "application" => "example",
            "redirects" => [],
            "type" => "sso",
            "vhost_properties" => {},
            "cert" => 'wildcard_timgroup_com',
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
            "cert" => 'wildcard_timgroup_com',
          },
          "example-sso.overridden" => {
            "proxy_pass_rules" => {
              "/" => "http://e1-exampleapp2-vip.space.net.local:8000"
            },
            "aliases" => [
              "e1-exampleproxy-sso-vip.front.space.net.local",
              "e1-exampleproxy-sso-vip.space.net.local"
            ],
            "application" => "example",
            "redirects" => [],
            "type" => "sso",
            "vhost_properties" => {},
            "cert" => 'wildcard_timgroup_com',
          }
        },
        "prod_vip_fqdn" => "e1-exampleproxy-vip.space.net.local",
        "environment" => "e1"
      }
    })
  end
end

describe_stack 'proxy servers can have the default ssl cert and vhost ssl certs overriden' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        set_default_ssl_cert 'test_cert_change'
        vhost('exampleapp') do
          with_cert 'test_vhost_cert_change'
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
    enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['cert'].should eql('test_vhost_cert_change')
  end
end
