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
        self.ports = [80,443,8443]
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

    env "e1", :primary_site=>"space",
      'exampleproxy.vhost.exampleapp2.server_name' => 'example.overridden',
      'exampleproxy.vhost.exampleapp2-sso.server_name' => 'example-sso.overridden' do
      instantiate_stack "exampleproxy"
      end
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql(
      {"role::proxyserver"=>{
      "vhosts"=>{
        "e1-exampleproxy-vip.front.space.net.local"=>{
          "proxy_pass_rules"=>{
            "/"=>"http://e1-exampleapp-vip.space.net.local:8000"
          },
          "aliases"=>["e1-exampleproxy-vip.space.net.local"],
          "application"=>"example",
          "redirects"=>[]},

        "e1-exampleproxy-sso-vip.front.space.net.local"=>{
          "proxy_pass_rules"=>{
            "/"=>"http://e1-exampleapp-vip.space.net.local:8000"},
            "aliases"=>[
            "e1-exampleproxy-sso-vip.space.net.local"],
            "application"=>"example",
            "redirects"=>[]},

        "example.overridden"=>{
          "proxy_pass_rules"=>{
            "/"=>"http://e1-exampleapp2-vip.space.net.local:8000"
          },
          "aliases"=>["e1-exampleproxy-vip.front.space.net.local", "e1-exampleproxy-vip.space.net.local"],
          "application"=>"example",
          "redirects"=>[]},

        "example-sso.overridden"=>{
          "proxy_pass_rules"=>{
            "/"=>"http://e1-exampleapp2-vip.space.net.local:8000"},
            "aliases"=>[
              "e1-exampleproxy-sso-vip.front.space.net.local",
              "e1-exampleproxy-sso-vip.space.net.local"],
            "application"=>"example",
            "redirects"=>[]}},
        "prod_vip_fqdn"=>"e1-exampleproxy-vip.space.net.local"}})
  end
end
