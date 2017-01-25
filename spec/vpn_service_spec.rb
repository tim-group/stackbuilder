
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'test enc of vpn servers' do
  given do
    stack 'nat' do
      nat_service
    end

    stack 'lb' do
      loadbalancer_service
    end

    stack 'vpn_stack' do
      vpn_service 'vpn' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name, :nat_to_vip
        each_machine do |machine|
          machine.add_vpn_network(:prod, 'ldn-office.youdevise.com', '172.16.0.0/21', '10.108.0.0/16')
          machine.add_vpn_network(:prod, 'ldn-office.youdevise.com', '172.16.0.0/21', '10.111.0.0/16')
          machine.add_vpn_network(:prod, 'ldn-office.youdevise.com', '172.16.0.0/21', '172.20.0.0/16')
        end
      end
    end

    env 'oymigration', :primary_site => 'oy', :vpn_virtual_router_id => 101 do
      instantiate_stack 'lb'
      instantiate_stack 'vpn_stack'
      instantiate_stack 'nat'
    end
  end

  # OY Master
  host('oymigration-vpn-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::vpn']).to(
      eql(
        'vpns' => {
          'oymigration-vpn-vip.oy.net.local' => {
            'ldn-office.youdevise.com' => {
              '172.16.0.0/21' => [
                '10.108.0.0/16',
                '10.111.0.0/16',
                '172.20.0.0/16'
              ]
            }
          }
        },
        'virtual_servers' => {
          'oymigration-vpn-vip.oy.net.local' => {
            'type' => 'racoon'
          },
          'oymigration-vpn-vip.mgmt.oy.net.local' => {
            'type' => 'racoon'
          }
        },
        'virtual_router_id' => 101
      )
    )
  end

  host('oymigration-lb-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::loadbalancer']).to eql('virtual_router_id' => 1,
                                             'virtual_servers' => {})
  end

  host('oymigration-nat-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    nat_role_dnat = enc['role::natserver']['rules']['DNAT']
    [500, 4500].each do |port|
      expect(nat_role_dnat["oymigration-vpn-vip.front.oy.net.local #{port}"]).to(
        eql(
          'dest_host' => 'oymigration-vpn-vip.oy.net.local',
          'dest_port' => "#{port}",
          'tcp' => false,
          'udp' => true
        )
      )
    end
  end
end
