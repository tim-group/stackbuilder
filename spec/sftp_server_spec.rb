require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'sftp servers should support load balancing and dependant instances' do
  given do
    stack "lb" do
      loadbalancer
    end

    stack "secureftp" do
      virtual_sftpserver 'sftp' do
        self.ports = ['2222']
      end
    end

    stack 'tim_cyclic' do
      standalone_appserver 'timcyclic' do
        self.groups = ['grey']
        self.application = 'TIM'
        self.instances = 2
        depend_on 'sftp'
      end
    end

    env "mirror", :primary_site => "oy", :secondary_site => "bs" do
      instantiate_stack "lb"
      instantiate_stack "tim_cyclic"
      instantiate_stack "secureftp"
    end
  end

  host("mirror-sftp-001.mgmt.oy.net.local") do |sftp_server|
    sftp_enc = sftp_server.to_enc
    expect(sftp_enc['role::sftpserver']['vip_fqdn']).to eql('mirror-sftp-vip.oy.net.local')
    expect(sftp_enc['role::sftpserver']['env']).to eql('mirror')
    expect(sftp_enc['role::sftpserver']['participation_dependant_instances']).to include(
      'mirror-lb-001.oy.net.local',
      'mirror-lb-002.oy.net.local'
    )
    expect(sftp_enc['role::sftpserver']['participation_dependant_instances'].size).to eql(2)
    expect(sftp_enc['role::sftpserver']['ssh_dependant_instances']).to include(
      'mirror-timcyclic-001.mgmt.oy.net.local',
      'mirror-timcyclic-002.mgmt.oy.net.local'
    )
    expect(sftp_enc['role::sftpserver']['ssh_dependant_instances'].size).to eql(2)
  end
  host("mirror-lb-001.mgmt.oy.net.local") do |load_balancer|
    lb_enc = load_balancer.to_enc
    expect(lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['persistent_ports']).
      to eql([])
    expect(lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['ports']).to eql(['2222'])
  end
end
describe_stack 'sftp servers should provide specific mounts' do
  given do
    stack "secureftp" do
      virtual_sftpserver 'sftp' do
        self.ports = ['2222']
      end
    end

    env "mirror", :primary_site => "oy", :secondary_site => "bs" do
      instantiate_stack "secureftp"
    end
  end

  host("mirror-sftp-001.mgmt.oy.net.local") do |sftp_server|
    storage = sftp_server.to_specs.shift[:storage]
    expect(storage.key?(:"/chroot")).to eql true
    expect(storage[:"/chroot"][:size]).to eql '40G'
    expect(storage[:"/chroot"][:persistent]).to eql true
    expect(storage.key?(:"/var/lib/batchelor")).to eql true
    expect(storage[:"/var/lib/batchelor"][:size]).to eql '40G'
    expect(storage[:"/var/lib/batchelor"][:persistent]).to eql true
    expect(storage.key?(:"/home")).to eql true
    expect(storage[:"/home"][:size]).to eql '20G'
    expect(storage[:"/home"][:persistent]).to eql true
    expect(storage.key?(:"/tmp")).to eql true
    expect(storage[:"/tmp"][:size]).to eql '10G'
  end
end
