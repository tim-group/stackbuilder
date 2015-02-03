require 'stacks/test_framework'

describe_stack 'test_app_server' do
  given do
    stack "test_app_server" do
      virtual_appserver "appx" do
        self.application="JavaHttpRef"
        each_machine do |machine|
          machine.launch_config['specify_config_as_system_property'] = 'yes'
        end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    host.to_enc['launch_config'].should eql({
      'specify_config_as_system_property' => 'yes'
    })
  end
end
