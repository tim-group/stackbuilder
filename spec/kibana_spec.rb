require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'kibana server enc is correct' do
  given do
    stack 'kibana_stack' do
      kibana do
        depend_on 'elasticsearch-data'
      end
      elasticsearch_data 'elasticsearch-data'
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'kibana_stack'
      end
    end
  end

  host('oy-kibana-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::kibana']).not_to be_nil
    expect(enc['role::kibana']['elasticsearch_cluster_address']).to eql('oy-elasticsearch-data-vip.oy.net.local')
  end
end
