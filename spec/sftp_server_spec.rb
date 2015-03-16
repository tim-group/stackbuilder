require 'stacks/test_framework'

describe_stack 'sftp servers' do
  given do
    stack "lb" do
      loadbalancer
    end

    stack "secureftp" do
      virtual_sftpserver 'sftp' do
      end
    end

    env "mirror", :primary_site => "oy", :secondary_site => "bs" do
      instantiate_stack "lb"
      instantiate_stack "secureftp"
    end
  end

  host("mirror-sftp-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    enc['role::sftpserver']['vip_fqdn'].should eql('mirror-sftp-vip.oy.net.local')
    enc['role::sftpserver']['env'].should eql('mirror')
    enc['role::sftpserver']['participation_dependant_instances'].should include(
      'mirror-lb-001.oy.net.local',
      'mirror-lb-002.oy.net.local'
    )
    enc['role::sftpserver']['participation_dependant_instances'].size.should eql(2)
  end
end
