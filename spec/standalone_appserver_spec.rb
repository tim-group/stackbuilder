require 'stacks/test_framework'

describe_stack 'tim' do
  given do
    stack 'tim' do
      standalone_appserver 'timcyclic' do
        self.application = 'TIM'
        self.instances = environment.options[:tim_instances] || 1
        each_machine do |machine|
          machine.ram = '14680064'
          machine.vcpus = '8'
          machine.modify_storage('/'.to_sym => { :size => '10G' })
        end
      end
    end
    env "e1", :primary_site => "space", :tim_instances => 2 do
      instantiate_stack "tim"
    end
  end

  host("e1-timcyclic-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    enc['role::http_app']['application'].should eql('TIM')
    enc['role::http_app']['group'].should eql('blue')
    enc['role::http_app']['cluster'].should eql('e1-timcyclic')
    enc['role::http_app']['environment'].should eql('e1')
    enc['role::http_app']['port'].should eql('8000')
    enc['role::http_app']['dependencies'].should eql({})
    enc['role::http_app']['dependant_instances'].should eql([])
  end
  host("e1-timcyclic-002.mgmt.space.net.local") do |host|
    host.to_specs.shift[:ram].should eql '14680064'
    host.to_specs.shift[:vcpus].should eql '8'
    host.to_specs.shift[:storage]['/'.to_sym][:size].should eql '10G'
  end
end

describe_stack 'app with sso port' do
  given do
    stack 'app' do
      standalone_appserver 'testssoapp' do
        self.application = 'testapp'
        enable_sso('8444')
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "app"
    end
  end

  host("e1-testssoapp-002.mgmt.space.net.local") do |host|
    host.to_enc['role::http_app']['sso_port'].should eql '8444'
  end
end

describe_stack 'app with ajp port' do
  given do
    stack 'app' do
      standalone_appserver 'testajpapp' do
        self.application = 'testapp'
        enable_ajp('8444')
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "app"
    end
  end

  host("e1-testajpapp-002.mgmt.space.net.local") do |host|
    host.to_enc['role::http_app']['ajp_port'].should eql '8444'
  end
end
