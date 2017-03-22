require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'machines get enc provided by their environment (or a specific provided environment)' do
  given do
    stack 'a_stack' do
      standard_service 'test'
      logstash_receiver 'logstash-receiver'
    end

    stack 'b_stack' do
      standard_service 'test'
    end

    env 'shared', :primary_site => 'oy' do
      depend_on 'logstash-receiver'
      instantiate_stack 'a_stack'
      env 'oy' do
        depend_on 'logstash-receiver', 'shared'
        instantiate_stack 'b_stack'
      end
    end
  end

  host('shared-test-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['profiles::filebeat']).not_to be_nil
    enc = enc['profiles::filebeat']
    expect(enc['logstash_receiver_hosts']).to be_eql([
      'shared-logstash-receiver-001.mgmt.oy.net.local',
      'shared-logstash-receiver-002.mgmt.oy.net.local'
    ])
  end

  host('oy-test-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['profiles::filebeat']).not_to be_nil
    enc = enc['profiles::filebeat']
    expect(enc['logstash_receiver_hosts']).to be_eql([
      'shared-logstash-receiver-001.mgmt.oy.net.local',
      'shared-logstash-receiver-002.mgmt.oy.net.local'
    ])
  end
end
