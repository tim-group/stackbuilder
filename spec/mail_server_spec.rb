require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'test enc of the mail servers' do
  given do
    stack "lb" do
      loadbalancer
    end

    stack 'mail_stack' do
      virtual_mailserver 'mail' do
        case environment.name
        when 'oymigration'
          allow_host '172.16.0.0/21'
        end
      end
    end

    env "oymigration", :primary_site => "oy" do
      instantiate_stack "lb"
      instantiate_stack "mail_stack"
    end
  end

  # OY Master
  host("oymigration-mail-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    enc['server::default_new_mgmt_net_local'].should be_nil
    enc['role::mail_server2']['allowed_hosts'].sort.should eql([
      '172.16.0.0/21',
    ])
    enc['role::mail_server2']['vip_fqdns'].sort.should eql([
      'oymigration-mail-vip.mgmt.oy.net.local',
    ])
    enc['role::mail_server2']['dependant_instances'].sort.should eql([
      'oymigration-lb-001.mgmt.oy.net.local',
      'oymigration-lb-002.mgmt.oy.net.local',
    ])
    enc['role::mail_server2']['participation_dependant_instances'].should eql([
      'oymigration-lb-001.mgmt.oy.net.local',
      'oymigration-lb-002.mgmt.oy.net.local',
    ])
    enc['role::mail_server2']['vip_networks'].should eql(['mgmt'])
  end
end
