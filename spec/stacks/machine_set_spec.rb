require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe 'Stacks::MachineSet' do
  describe_stack 'allows creation of secondary servers' do
    given do
      stack "funds" do
        app_service 'fundsapp' do
          self.instances = 1
          @enable_secondary_site = true
        end
      end

      env 'env', :primary_site => 'mars', :secondary_site => 'jupiter' do
        instantiate_stack 'funds'
      end
    end
    it_stack 'should contain 1 server in each site' do |stack|
      expect(stack).to have_host('env-fundsapp-001.mgmt.mars.net.local')
      expect(stack).to have_host('env-fundsapp-001.mgmt.jupiter.net.local')
    end
  end
  describe_stack 'provides an allowed host mechanism that can be used by app_services' do
    given do
      stack "mystack" do
        app_service "x" do
          allow_host '1.1.1.1'
          each_machine do |_machine|
            allow_host '2.2.2.2'
          end
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    it_stack 'allows specification of aditional hosts that are allowed to talk to the app or service' do
      host("e1-x-001.mgmt.space.net.local") do |host|
        expect(host.to_enc['role::http_app']['allowed_hosts']).to eql(['1.1.1.1', '2.2.2.2'])
      end
    end
  end
  describe_stack 'provides an allowed host mechanism that can be used by standalone_app_services' do
    given do
      stack "mystack" do
        standalone_app_service "x" do
          allow_host '1.1.1.1'
          each_machine do |_machine|
            allow_host '2.2.2.2'
          end
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    it_stack 'allows specification of aditional hosts that are allowed to talk to the app or service' do
      host("e1-x-001.mgmt.space.net.local") do |host|
        expect(host.to_enc['role::http_app']['allowed_hosts']).to eql(['1.1.1.1', '2.2.2.2'])
      end
    end
  end
end

describe_stack 'should support instances as a hash' do
  given do
    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.instances = { 'earth' => 0, 'jupiter' => 2 }
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.jupiter.net.local',
        'e1-appx-002.mgmt.jupiter.net.local'
      ]
    )
  end
end

describe_stack 'should support instances as a site hash' do
  given do
    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.instances = {
          'earth' => {
            :basic => 1
          },
          'jupiter' => 1
        }
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.earth.net.local',
        'e1-appx-001.mgmt.jupiter.net.local'
      ]
    )
  end
  host("e1-appx-001.mgmt.earth.net.local") do |host|
    expect(host.role).to eql(:basic)
  end
  host("e1-appx-001.mgmt.jupiter.net.local") do |host|
    expect(host.role).to be_nil
  end
end

describe_stack 'should raise exception for an un-supported site' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = { 'earth' => 0, 'jupiter' => 2, 'moon' => 0 }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/e1 environment does not support site\(s\): moon/)
end
