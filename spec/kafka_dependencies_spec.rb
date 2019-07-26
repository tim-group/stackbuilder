require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'kafka-stack-with-dependencies' do
  given do
    stack 'example_store' do
      kafka_cluster 'examplestore' do |cluster|
        self.kafka_name = 'examplestore'
        cluster.instances = { 'space' => 3 }
        cluster.each_machine do |machine|
          machine.template(:trusty)
          machine.ram = '4097152'
          machine.vcpus = '4'
        end
      end
    end

    stack 'example_appserver' do
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        self.instances = { 'space' => 2 }
        depend_on 'examplestore', environment.name
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_store'
      instantiate_stack 'example_appserver'
    end
  end

  host('e-examplestore-001.mgmt.space.net.local') do |host|
    deps = host.to_enc['role::kafka_server']
    expect(deps['dependant_instances']).to eql(["e-myapp-001.space.net.local", "e-myapp-002.space.net.local"])
  end

  host('e-myapp-001.mgmt.space.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['kafka.examplestore.cluster']).to eql(
      "e-examplestore-001.space.net.local,e-examplestore-002.space.net.local,e-examplestore-003.space.net.local")
  end
end
