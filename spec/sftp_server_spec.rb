require 'stacks/test_framework'

describe_stack 'sftp servers' do
  given do
    stack "lb" do
      loadbalancer
    end

    stack "secureftp" do
      virtual_sftpserver 'sftp' do
        self.ports = ['2222']
      end
    end

    env "mirror", :primary_site => "oy", :secondary_site => "bs" do
      instantiate_stack "lb"
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
  end
  host("mirror-lb-001.mgmt.oy.net.local") do |load_balancer|
    lb_enc = load_balancer.to_enc
    lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['persistent_ports'].should eql([])
    lb_enc['role::loadbalancer']['virtual_servers']['mirror-sftp-vip.oy.net.local']['ports'].should eql(['2222'])
  end
end
