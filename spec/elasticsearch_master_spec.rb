require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'elasticsearch master server enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data' do
        depend_on 'elasticsearch-master'
      end
      elasticsearch_master 'elasticsearch-master'
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'a_stack'
      end
    end
  end

  host('oy-elasticsearch-master-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::elasticsearch_master']).not_to be_nil
    expect(enc['role::elasticsearch_master']['elasticsearch_data_hosts']).to \
      eql([
        'oy-elasticsearch-data-001.oy.net.local',
        'oy-elasticsearch-data-002.oy.net.local'
      ])
  end
end
