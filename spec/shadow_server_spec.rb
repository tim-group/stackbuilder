require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack "rabbit" do
      virtual_rabbitmqserver 'rabbitmq'
    end
    stack "shadow" do
      shadow_server "oy-mon-001" do
        depend_on 'rabbitmq'
        each_machine do |machine|
          machine.hostname = 'oy-mon-001'
          machine.domain = 'oy.net.local'
        end
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "shadow"
      instantiate_stack "rabbit"
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    host.to_enc["role::rabbitmq_server"]["dependant_instances"].should eql([
      'oy-mon-001.oy.net.local'
    ])
  end
end
