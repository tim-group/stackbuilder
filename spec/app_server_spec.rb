require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'test_app_server' do
  given do
    stack "test_app_server" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
        each_machine do |machine|
          machine.launch_config['specify_config_as_system_property'] = 'yes'
        end
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['launch_config']).to eql('specify_config_as_system_property' => 'yes')
  end
end

describe_stack 'test_app_server should default to no jvm args' do
  given do
    stack "test_app_server" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app'].key?('jvm_args')).to eql(false)
  end
end

describe_stack 'test_app_server with custom jvm args' do
  given do
    stack "test_app_server" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
        @jvm_args = '-Xms256m -Xmx256m -XX:CMSInitiatingOccupancyFraction=55 -XX:+UseCompressedOops ' \
          '-XX:+UseConcMarkSweepGC -XX:MaxPermSize=128M -XX:+CMSClassUnloadingEnabled'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['jvm_args']).to eql('-Xms256m -Xmx256m ' \
      '-XX:CMSInitiatingOccupancyFraction=55 -XX:+UseCompressedOops -XX:+UseConcMarkSweepGC ' \
      '-XX:MaxPermSize=128M -XX:+CMSClassUnloadingEnabled')
  end
end

describe_stack 'test_app_server with only one instance in the load balancer' do
  given do
    stack "test_app_server" do
      loadbalancer do
      end
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
        @one_instance_in_lb = true
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-lb-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::loadbalancer']['virtual_servers']['e1-appx-vip.space.net.local']
    expect(enc['type']).to eql 'one_instance_in_lb_with_sorry_server'
  end
end

describe_stack 'should have the correct app_dependant_instances and participation_dependant_instances' do
  given do
    stack 'loadbalancer' do
      loadbalancer do
      end
    end

    stack 'example' do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
      end
      virtual_appserver "appy" do
        self.application = "JavaHttpRef"
        depend_on "appx"
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "loadbalancer"
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.space.net.local',
        'e1-appx-002.mgmt.space.net.local',
        'e1-appy-001.mgmt.space.net.local',
        'e1-appy-002.mgmt.space.net.local',
        'e1-lb-001.mgmt.space.net.local',
        'e1-lb-002.mgmt.space.net.local'
      ]
    )
  end

  host("e1-appy-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::http_app']
    pp enc
    expect(enc['participation_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                                'e1-lb-002.space.net.local')
    expect(enc['participation_dependant_instances'].size).to eql(2)
    expect(enc['application_dependant_instances']).to include('e1-lb-001.space.net.local', 'e1-lb-002.space.net.local')
    expect(enc['application_dependant_instances'].size).to eql(2)
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::http_app']
    expect(enc['participation_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                                'e1-lb-002.space.net.local')
    expect(enc['participation_dependant_instances'].size).to eql(2)
    expect(enc['application_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                              'e1-lb-002.space.net.local',
                                                              'e1-appy-001.space.net.local',
                                                              'e1-appy-002.space.net.local')
    expect(enc['application_dependant_instances'].size).to eql(4)
  end
end
