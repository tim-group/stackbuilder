require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack "rabbit" do
      rabbitmq_cluster 'rabbitmq'
    end
    stack "external" do
      external_service "oy-mon-001.oy.net.local" do
        depend_on 'rabbitmq', environment.name, 'external'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "external"
      instantiate_stack "rabbit"
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc["role::rabbitmq_server"]["dependant_instances"]).to include('oy-mon-001.oy.net.local')
  end
end
