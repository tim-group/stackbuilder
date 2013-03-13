require 'stacks/environment'
require 'stacks/proxy_server'

describe Stacks::ProxyServer do

  it 'allows us to use other CNAMES other than the generated front name' do

  end

  it 'blows us if we attempt to use make two vhosts with the same name' do
    proxy_virtualservice = Stacks::VirtualService.new("proxy", :AppServer)
    app_virtualservice = Stacks::VirtualService.new("app", :AppServer)
    appserver = Stacks::AppServer.new(app_virtualservice, "001")
    proxyserver = Stacks::ProxyServer.new("proxy-001", proxy_virtualservice)
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})

    proxy_virtualservice.bind_to(env)
    app_virtualservice.bind_to(env)
    appserver.bind_to(env)

    proxyserver.create_vhost("app") do
      with_alias "example.timgroup.com"
    end

    proxyserver.create_vhost("app2") do
      with_alias "example.timgroup.com"
    end

    proxyserver.bind_to(env)

    env.instance_eval do
      @machine_def_containers["app"] = app_virtualservice
      @machine_def_containers["proxy"] = proxy_virtualservice
    end

    expect {proxyserver.to_enc}.to raise_error
  end


  it 'produces an enc references the downstream virtual service it is proxying' do
    proxy_virtualservice = Stacks::VirtualService.new("proxy", :AppServer)
    app_virtualservice = Stacks::VirtualService.new("app", :AppServer)
    appserver = Stacks::AppServer.new(app_virtualservice, "001")
    proxyserver = Stacks::ProxyServer.new("proxy-001", proxy_virtualservice)
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})

    proxy_virtualservice.bind_to(env)
    app_virtualservice.bind_to(env)
    appserver.bind_to(env)

    proxyserver.create_vhost("app") do
      with_alias "example.timgroup.com"
    end

    proxyserver.bind_to(env)

    env.instance_eval do
      @machine_def_containers["app"] = app_virtualservice
      @machine_def_containers["proxy"] = proxy_virtualservice
    end

    proxyserver.to_enc.should eql(
      {'role::httpproxy'=> {
          'env-proxy-vip.front.st.net.local' => {
            'balancer_members' => ["env-app-vip.st.net.local"],
            'aliases' => ['example.timgroup.com']
          }
        }
      })
  end
end
