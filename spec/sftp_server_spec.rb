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
    sftp_enc['role::sftpserver']['vip_fqdn'].should eql('mirror-sftp-vip.oy.net.local')
    sftp_enc['role::sftpserver']['env'].should eql('mirror')
    sftp_enc['role::sftpserver']['participation_dependant_instances'].should include(
      'mirror-lb-001.oy.net.local',
      'mirror-lb-002.oy.net.local'
    )
    sftp_enc['role::sftpserver']['participation_dependant_instances'].size.should eql(2)
    sftp_enc['role::sftpserver']['ssh_dependant_instances'].should include(
      'mirror-timcyclic-001.mgmt.oy.net.local',
      'mirror-timcyclic-002.mgmt.oy.net.local'
    )
    sftp_enc['role::sftpserver']['ssh_dependant_instances'].size.should eql(2)
  end
  host("mirror-lb-001.mgmt.oy.net.local") do |load_balancer|
    lb_enc = load_balancer.to_enc
    lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['persistent_ports'].should eql([])
    lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['ports'].should eql(['2222'])
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
    storage.key?(:"/chroot").should eql true
    storage[:"/chroot"][:size].should eql '40G'
    storage[:"/chroot"][:persistent].should eql true
    storage.key?(:"/var/lib/batchelor").should eql true
    storage[:"/var/lib/batchelor"][:size].should eql '40G'
    storage[:"/var/lib/batchelor"][:persistent].should eql true
    storage.key?(:"/home").should eql true
    storage[:"/home"][:size].should eql '20G'
    storage[:"/home"][:persistent].should eql true
    storage.key?(:"/tmp").should eql true
    storage[:"/tmp"][:size].should eql '10G'
  end
end
