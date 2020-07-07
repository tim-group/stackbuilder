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
        app_service 'dumbapp' do
          self.instances = 1
          @enable_secondary_site = false
        end
      end

      env 'env', :primary_site => 'mars', :secondary_site => 'jupiter' do
        instantiate_stack 'funds'
      end
    end
    it_stack 'should contain 1 server in each site' do |stack|
      expect(stack).to have_host('env-fundsapp-001.mgmt.mars.net.local')
      expect(stack).to have_host('env-fundsapp-001.mgmt.jupiter.net.local')
      expect(stack).to have_host('env-dumbapp-001.mgmt.mars.net.local')
      expect(stack).not_to have_host('env-dumbapp-001.mgmt.jupiter.net.local')
    end
    it_stack 'should put secondary site server in a different cluster' do |stack|
      expect(stack.find("env-fundsapp-001.mgmt.mars.net.local").to_enc['role::http_app']['cluster']).to eql('env-fundsapp-mars')
      expect(stack.find("env-fundsapp-001.mgmt.jupiter.net.local").to_enc['role::http_app']['cluster']).to eql('env-fundsapp-jupiter')
      expect(stack.find("env-dumbapp-001.mgmt.mars.net.local").to_enc['role::http_app']['cluster']).to eql('env-dumbapp')
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
          'earth'   => 1,
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
    expect(host.role).to be_nil
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

describe_stack 'should raise exception if instance count provided is a string with basic @instances(Hash)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = { 'earth' => '1' }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integers when using @instances in a hash format/)
end

describe_stack 'should raise exception if instance count provided is a string with role based @instances(Hash)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = {
            'earth' => {
              :fish => '1'
            }
          }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integers when using @instances in a hash format/)
end

describe_stack 'should raise exception if @instances is not an Integer or Hash' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = 'go fish'
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integer or Hash for @instances. You provided a String/)

  describe_stack 'allows monitoring to be changed at machineset level' do
    given do
      stack "mystack" do
        app_service "x" do
          self.monitoring_in_enc = true
          self.monitoring = false
          self.monitoring_options = {}
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.space.net.local") do |host|
      expect(host.to_enc['monitoring']['checks']).to eql(false)
      expect(host.to_enc['monitoring']['options']).to eql({})
    end
  end
end
