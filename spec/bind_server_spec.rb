require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'nameservers with bi-directional slave_from dependencies' do
  given do
    stack "lb" do
      loadbalancer_service
    end

    stack "nameserver" do
      bind_service 'ns' do
        enable_nat
        forwarder_zone(['youdevise.com'])
        case environment.name
        when 'pg'
          depend_on 'ns', 'oy'
        when 'oy'
          depend_on 'ns', 'pg'
        end
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
        instantiate_stack "lb"
      end
    end

    env "p", :primary_site => "pg" do
      env 'pg' do
        instantiate_stack "nameserver"
        instantiate_stack "lb"
      end
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'oy-ns-001.mgmt.oy.net.local',
        'oy-ns-002.mgmt.oy.net.local',
        'pg-ns-001.mgmt.pg.net.local',
        'pg-ns-002.mgmt.pg.net.local',
        'oy-lb-001.mgmt.oy.net.local',
        'oy-lb-002.mgmt.oy.net.local',
        'pg-lb-001.mgmt.pg.net.local',
        'pg-lb-002.mgmt.pg.net.local'
      ]
    )
  end

  # OY Master - Slaves from PG Master
  host("oy-ns-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to eql([
      'mgmt.oy.net.local',
      'oy.net.local',
      'front.oy.net.local'
    ])
    expect(enc['role::bind_server']['slave_zones']).
      to eql('pg-ns-001.mgmt.pg.net.local' => ['mgmt.pg.net.local', 'pg.net.local', 'front.pg.net.local'])
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.mgmt.oy.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.oy.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-001.mgmt.pg.net.local',
      'pg-ns-002.mgmt.pg.net.local',
      'oy-ns-002.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(3)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'oy-lb-001.mgmt.oy.net.local',
      'oy-lb-001.oy.net.local',
      'oy-lb-002.mgmt.oy.net.local',
      'oy-lb-002.oy.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
  end
  # OY Slave - Slaves from OY Master, PG Master
  host("oy-ns-002.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to be_nil
    expect(enc['role::bind_server']['slave_zones']).to eql(
      'oy-ns-001.mgmt.oy.net.local' => ['mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'],
      'pg-ns-001.mgmt.pg.net.local' => ['mgmt.pg.net.local', 'pg.net.local', 'front.pg.net.local']
    )
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.mgmt.oy.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.oy.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'oy-ns-001.mgmt.oy.net.local',
      'pg-ns-001.mgmt.pg.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(2)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'oy-lb-001.mgmt.oy.net.local',
      'oy-lb-001.oy.net.local',
      'oy-lb-002.mgmt.oy.net.local',
      'oy-lb-002.oy.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
  end

  # PG Master - Slaves from OY Master
  host("pg-ns-001.mgmt.pg.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to eql([
      'mgmt.pg.net.local',
      'pg.net.local',
      'front.pg.net.local'
    ])
    expect(enc['role::bind_server']['slave_zones']).
      to eql('oy-ns-001.mgmt.oy.net.local' => ['mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'])
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.mgmt.pg.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.pg.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-002.mgmt.pg.net.local',
      'oy-ns-001.mgmt.oy.net.local',
      'oy-ns-002.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(3)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'pg-lb-001.mgmt.pg.net.local',
      'pg-lb-001.pg.net.local',
      'pg-lb-002.mgmt.pg.net.local',
      'pg-lb-002.pg.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
  end

  # PG Slave - Slaves from PG Master, OY Master
  host("pg-ns-002.mgmt.pg.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to be_nil
    expect(enc['role::bind_server']['slave_zones']).to eql('oy-ns-001.mgmt.oy.net.local' => [
      'mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'
    ],
                                                           'pg-ns-001.mgmt.pg.net.local' => [
                                                             'mgmt.pg.net.local', 'pg.net.local', 'front.pg.net.local'
                                                           ])
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.mgmt.pg.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.pg.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-001.mgmt.pg.net.local',
      'oy-ns-001.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(2)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'pg-lb-001.mgmt.pg.net.local',
      'pg-lb-001.pg.net.local',
      'pg-lb-002.mgmt.pg.net.local',
      'pg-lb-002.pg.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
  end
end

describe_stack 'nameservers with single slave_from dependency' do
  given do
    stack "lb" do
      loadbalancer_service
    end

    stack "nameserver" do
      bind_service 'ns' do
        enable_nat
        forwarder_zone(['youdevise.com'])
        case environment.name
        when 'pg'
          depend_on 'ns', 'oy'
        end
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
        instantiate_stack "lb"
      end
    end

    env "p", :primary_site => "pg" do
      env 'pg' do
        instantiate_stack "nameserver"
        instantiate_stack "lb"
      end
    end
  end
  # OY Master
  host("oy-ns-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to eql([
      'mgmt.oy.net.local',
      'oy.net.local',
      'front.oy.net.local'
    ])
    expect(enc['role::bind_server']).not_to have_key('slave_zones')
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.mgmt.oy.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.oy.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-001.mgmt.pg.net.local',
      'pg-ns-002.mgmt.pg.net.local',
      'oy-ns-002.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(3)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'oy-lb-001.mgmt.oy.net.local',
      'oy-lb-001.oy.net.local',
      'oy-lb-002.mgmt.oy.net.local',
      'oy-lb-002.oy.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
    Resolv.stub(:getaddress).with('oy-ns-002.mgmt.oy.net.local').and_return('4.3.2.1')
    expect(host.to_spec[:nameserver]).to eql('4.3.2.1')
    expect(host.virtual_service.vip_networks).to be_eql [:mgmt, :front, :prod]
  end
  # OY Slave - Slaves from OY Master
  host("oy-ns-002.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to be_nil
    expect(enc['role::bind_server']['slave_zones']).
      to eql('oy-ns-001.mgmt.oy.net.local' => ['mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'])
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.mgmt.oy.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('oy-ns-vip.oy.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to eql(['oy-ns-001.mgmt.oy.net.local'])
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'oy-lb-001.mgmt.oy.net.local',
      'oy-lb-001.oy.net.local',
      'oy-lb-002.mgmt.oy.net.local',
      'oy-lb-002.oy.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
    Resolv.stub(:getaddress).with('oy-ns-001.mgmt.oy.net.local').and_return('1.2.3.4')
    expect(host.to_spec[:nameserver]).to eql('1.2.3.4')
  end

  # PG Master - Slaves from OY Master
  host("pg-ns-001.mgmt.pg.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to eql([
      'mgmt.pg.net.local',
      'pg.net.local',
      'front.pg.net.local'
    ])
    expect(enc['role::bind_server']['slave_zones']).
      to eql('oy-ns-001.mgmt.oy.net.local' => ['mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'])
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.mgmt.pg.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.pg.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-002.mgmt.pg.net.local',
      'oy-ns-001.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(2)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'pg-lb-001.mgmt.pg.net.local',
      'pg-lb-001.pg.net.local',
      'pg-lb-002.mgmt.pg.net.local',
      'pg-lb-002.pg.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
  end

  # PG Slave - Slaves from PG Master, OY Master
  host("pg-ns-002.mgmt.pg.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to be_nil
    expect(enc['role::bind_server']['master_zones']).to be_nil
    expect(enc['role::bind_server']['slave_zones']).to eql('oy-ns-001.mgmt.oy.net.local' => [
      'mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'
    ],
                                                           'pg-ns-001.mgmt.pg.net.local' => [
                                                             'mgmt.pg.net.local', 'pg.net.local', 'front.pg.net.local'
                                                           ])
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.mgmt.pg.net.local')
    expect(enc['role::bind_server']['vip_fqdns']).to include('pg-ns-vip.pg.net.local')
    expect(enc['role::bind_server']['dependant_instances']).to include(
      'pg-ns-001.mgmt.pg.net.local',
      'oy-ns-001.mgmt.oy.net.local'
    )
    expect(enc['role::bind_server']['dependant_instances'].size).to eql(2)
    expect(enc['role::bind_server']['participation_dependant_instances']).to eql([
      'pg-lb-001.mgmt.pg.net.local',
      'pg-lb-001.pg.net.local',
      'pg-lb-002.mgmt.pg.net.local',
      'pg-lb-002.pg.net.local'
    ])
    expect(enc['role::bind_server']['forwarder_zones']).to eql(['youdevise.com'])
    expect(host.to_spec[:networks]).to be_eql([:mgmt, :prod])
    expect(host.to_spec[:qualified_hostnames]).to eql(:prod => 'pg-ns-002.pg.net.local',
                                                      :mgmt => 'pg-ns-002.mgmt.pg.net.local')
  end
end

describe_stack 'nameservers should have working load balancer and nat configuration' do
  given do
    stack "nat" do
      nat_service
    end

    stack "lb" do
      loadbalancer_service
    end

    stack "nameserver" do
      bind_service 'ns' do
        enable_nat
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
        instantiate_stack "nat"
        instantiate_stack "lb"
      end
    end

    env "p", :primary_site => "pg" do
      env 'pg' do
        instantiate_stack "nameserver"
        instantiate_stack "nat"
        instantiate_stack "lb"
      end
    end
  end

  host("oy-nat-001.mgmt.oy.net.local") do |host|
    expect(host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['dest_host']).
      to eql('oy-ns-vip.oy.net.local')
    expect(host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['dest_port']).to eql('53')
    expect(host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['tcp']).to eql(true)
    expect(host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']['udp']).to eql(true)
  end

  host("oy-lb-001.mgmt.oy.net.local") do |host|
    expect(host.to_enc['role::loadbalancer']['virtual_servers']['oy-ns-vip.oy.net.local']['healthchecks']).to include(
      {
        'healthcheck' => 'MISC_CHECK',
        'arg_style' => 'APPEND_HOST',
        'path' => '/usr/bin/host -4 -W 3 -t A -s apt.mgmt.oy.net.local'
      },
      {
        'healthcheck' => 'MISC_CHECK',
        'arg_style' => 'APPEND_HOST',
        'path' => '/usr/bin/host -4 -W 3 -t A -s gw-vip.front.oy.net.local'
      },
      {
        'healthcheck' => 'MISC_CHECK',
        'arg_style' => 'APPEND_HOST',
        'path' => '/usr/bin/host -4 -W 3 -t A -s gw-vip.oy.net.local'
      },
      'healthcheck' => 'MISC_CHECK',
      'arg_style' => 'PARTICIPATION',
      'path' => '/opt/youdevise/keepalived/healthchecks/bin/check_participation.rb',
      'url_path' => '/participation'
    )
  end
end

describe_stack 'bind servers without nat enabled should only have ips on mgmt by default' do
  given do
    stack "nat" do
      nat_service
    end

    stack "lb" do
      loadbalancer_service
    end

    stack "nameserver" do
      bind_service 'ns' do
        each_machine do |machine|
          machine.remove_network :prod
        end
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
        instantiate_stack "nat"
        instantiate_stack "lb"
      end
    end
  end

  host("oy-ns-001.mgmt.oy.net.local") do |host|
    expect(host.virtual_service.vip_networks).to be_eql [:mgmt]
    expect(host.to_enc['role::bind_server']['vip_fqdns']).to eql(['oy-ns-vip.mgmt.oy.net.local'])
    expect(host.to_spec[:networks]).to eql([:mgmt])
    expect(host.to_spec[:qualified_hostnames]).to be_eql(:mgmt => 'oy-ns-001.mgmt.oy.net.local')
  end

  host("oy-nat-001.mgmt.oy.net.local") do |host|
    expect(host.to_enc['role::natserver']['rules']['DNAT']['oy-ns-vip.front.oy.net.local 53']).to be_nil
  end

  host("oy-lb-001.mgmt.oy.net.local") do |host|
    expect(host.to_enc['role::loadbalancer']['virtual_servers']['oy-ns-vip.oy.net.local']).to be_nil
    expect(host.to_enc['role::loadbalancer']['virtual_servers']['oy-ns-vip.mgmt.oy.net.local']).not_to be_nil
  end
end

describe_stack 'bind servers with zones removed should have the right zone files' do
  given do
    stack "nameserver" do
      bind_service 'ns' do
        remove_zone :front
        remove_zone :prod
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
      end
    end
  end

  host("oy-ns-001.mgmt.oy.net.local") do |host|
    expect(host.virtual_service.zones).to be_eql [:mgmt]
  end
end

describe_stack 'test @slave_instances = 2' do
  given do
    stack "nameserver" do
      bind_service 'ns' do
        self.slave_instances = 2
      end
    end

    env "o", :primary_site => "oy" do
      env 'oy' do
        instantiate_stack "nameserver"
      end
    end
  end

  host("oy-ns-003.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['role::bind_server']['slave_zones']).
      to eql('oy-ns-001.mgmt.oy.net.local' => ['mgmt.oy.net.local', 'oy.net.local', 'front.oy.net.local'])
  end
end
