require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack "rabbit" do
      virtual_rabbitmqserver 'rabbitmq'
    end
    stack "external" do
      external_server "oy-mon-001.oy.net.local" do
        depend_on 'rabbitmq'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "external"
      instantiate_stack "rabbit"
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    host.to_enc["role::rabbitmq_server"]["dependant_instances"].should eql([
      'oy-mon-001.oy.net.local'
    ])
  end
end
