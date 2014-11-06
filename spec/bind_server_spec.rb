require 'stacks/test_framework'

describe_stack 'nameserver' do
  given do
    stack "nat" do
      natserver
    end

    stack "lb" do
      loadbalancer
    end

    stack "nameserver" do
      virtual_bindserver 'ns' do
        enable_nat
        forwarder_zone(['youdevise.com'])
        each_machine do |machine|
          case environment.name
          when 'pg'
            machine.slave_from 'oy'
    #      when 'oy'
    #        machine.slave_from 'pg'
          end
        end
      end
    end

    env "oy", :primary_site=>"oy" do
      instantiate_stack "nameserver"
      instantiate_stack "nat"
      instantiate_stack "lb"
    end

    env "pg", :primary_site=>"pg" do
      instantiate_stack "nameserver"
      instantiate_stack "nat"
      instantiate_stack "lb"
    end
  end

  # Master
  host("oy-ns-001.mgmt.oy.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['master_zones'].should eql([
        'mgmt.oy.net.local',
        'oy.net.local',
        'front.oy.net.local',
    ])
    host.to_enc['role::bind_server']['slave_zones'].should be_nil
    host.to_enc['role::bind_server']['vip_fqdns'].should include('oy-ns-vip.mgmt.oy.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('oy-ns-vip.oy.net.local')
    host.to_enc['role::bind_server']['dependant_instances'].should eql([
        'oy-ns-001.mgmt.oy.net.local',
        'oy-ns-002.mgmt.oy.net.local',
        'pg-ns-001.mgmt.pg.net.local',
        'pg-ns-002.mgmt.pg.net.local'
    ])
    host.to_enc['role::bind_server']['participation_dependant_instances'].should eql([
        'oy-lb-001.mgmt.oy.net.local',
        'oy-lb-001.oy.net.local',
        'oy-lb-002.mgmt.oy.net.local',
        'oy-lb-002.oy.net.local'
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql(['youdevise.com'])
  end
  # BIND SLAVE
  host("oy-ns-002.mgmt.oy.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['master_zones'].should be_nil
    host.to_enc['role::bind_server']['slave_zones'].should eql({
      'oy-ns-001.mgmt.oy.net.local' => [
         'mgmt.oy.net.local','oy.net.local','front.oy.net.local'
      ]
    })
    host.to_enc['role::bind_server']['vip_fqdns'].should include('oy-ns-vip.mgmt.oy.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('oy-ns-vip.oy.net.local')
    host.to_enc['role::bind_server']['dependant_instances'].should eql([
        'oy-ns-001.mgmt.oy.net.local',
        'oy-ns-002.mgmt.oy.net.local',
    ])
    host.to_enc['role::bind_server']['participation_dependant_instances'].should eql([
        'oy-lb-001.mgmt.oy.net.local',
        'oy-lb-001.oy.net.local',
        'oy-lb-002.mgmt.oy.net.local',
        'oy-lb-002.oy.net.local'
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql([
      'youdevise.com'
    ])
  end

  # PG master will slave from BIND master in OY
  host("pg-ns-001.mgmt.pg.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['master_zones'].should eql([
      'mgmt.pg.net.local',
      'pg.net.local',
      'front.pg.net.local',
    ])
    host.to_enc['role::bind_server']['slave_zones'].should eql({
      'oy-ns-001.mgmt.oy.net.local' => [
         'mgmt.oy.net.local','oy.net.local','front.oy.net.local'
      ]
    })
    host.to_enc['role::bind_server']['vip_fqdns'].should include('pg-ns-vip.mgmt.pg.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('pg-ns-vip.pg.net.local')
    host.to_enc['role::bind_server']['dependant_instances'].should eql([
        'pg-ns-001.mgmt.pg.net.local',
        'pg-ns-002.mgmt.pg.net.local',
        'oy-ns-001.mgmt.oy.net.local',
        'oy-ns-002.mgmt.oy.net.local', #i should not be here
    ])
    host.to_enc['role::bind_server']['participation_dependant_instances'].should eql([
        'pg-lb-001.mgmt.pg.net.local',
        'pg-lb-002.mgmt.pg.net.local',
        'pg-lb-001.pg.net.local',
        'pg-lb-002.pg.net.local'
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql([
      'youdevise.com'
    ])
  end

  # PG slave will slave from BIND master in OY and PG
  host("pg-ns-002.mgmt.pg.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['master_zones'].should be_nil
    host.to_enc['role::bind_server']['slave_zones'].should eql({
      'oy-ns-001.mgmt.oy.net.local' => [
         'mgmt.oy.net.local','oy.net.local','front.oy.net.local'
      ],
      'pg-ns-001.mgmt.pg.net.local' => [
         'mgmt.pg.net.local','pg.net.local','front.pg.net.local'
      ]
    })
    host.to_enc['role::bind_server']['vip_fqdns'].should include('pg-ns-vip.mgmt.pg.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('pg-ns-vip.pg.net.local')
    host.to_enc['role::bind_server']['dependant_instances'].should eql([
        'pg-ns-001.mgmt.pg.net.local',
        'pg-ns-002.mgmt.pg.net.local',
        'oy-ns-001.mgmt.oy.net.local',
    ])
    host.to_enc['role::bind_server']['participation_dependant_instances'].should eql([
        'pg-lb-001.mgmt.pg.net.local',
        'pg-lb-002.mgmt.pg.net.local',
        'pg-lb-001.pg.net.local',
        'pg-lb-002.pg.net.local'
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql([
      'youdevise.com'
    ])
  end





  host("oy-nat-001.mgmt.oy.net.local") do |host|
    host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['dest_host'].should eql('oy-ns-vip.oy.net.local')
    host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['dest_port'].should eql('53')
    host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['tcp'].should eql('true')
    host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['udp'].should eql('true')
  end

  host("oy-lb-001.mgmt.oy.net.local") do |host|
    host.to_enc['role::loadbalancer']['virtual_servers']['oy-ns-vip.oy.net.local']['healthchecks'].should include(
      {'healthcheck'=>'MISC_CHECK','arg_style'=>'APPEND_HOST','path'=>'/usr/bin/host -4 -W 3 -t A -s apt.mgmt.oy.net.local'},
      {'healthcheck'=>'MISC_CHECK','arg_style'=>'APPEND_HOST','path'=>'/usr/bin/host -4 -W 3 -t A -s gw-vip.front.oy.net.local'},
      {'healthcheck'=>'MISC_CHECK','arg_style'=>'APPEND_HOST','path'=>'/usr/bin/host -4 -W 3 -t A -s gw-vip.oy.net.local'},
      {
        'healthcheck'=>'MISC_CHECK',
        'arg_style'  =>'PARTICIPATION',
        'path'       =>'/opt/youdevise/keepalived/healthchecks/bin/check_participation.rb',
        'url_path'   =>'/participation'
      }
    )
  end
end
