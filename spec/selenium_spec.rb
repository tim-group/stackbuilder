require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'selenium' do
  given do
    stack "segrid" do
      selenium_version = "2.41.0"
      hub = selenium_hub('hub-001', :selenium_deb_version => selenium_version)
      selenium_node_cluster "a" do
        self.hub = hub
        self.nodespecs = [
          {
            :type => "ubuntu",
            :instances => 5,
            :firefox_version => "36.0+build2-0ubuntu0.12.04.5",
            :chrome_version => "12.4+banana",
            :selenium_deb_version => selenium_version,
            :lsbdistcodename => :trusty
          },
          {
            :type => "winxp",
            :instances => 2,
            :ie_version => "6",
            :gold_image => "file:///var/local/images/dev-sxp-gold.img",
            :selenium_version => selenium_version
          },
          {
            :type => "win7",
            :instances => 2,
            :ie_version => "9",
            :gold_image => "http://iso.youdevise.com/gold/win7-ie9-gold.img",
            :selenium_version => selenium_version
          },
          {
            :type => "win7",
            :instances => 1,
            :ie_version => "10",
            :gold_image => "http://iso.youdevise.com/gold/win7-ie10-gold.img",
            :selenium_version => selenium_version
          }
        ]
      end
    end

    stack "qatestmachines" do
      selenium_node_cluster "a" do
        self.nodespecs = [
          {
            :type => "ubuntu",
            :instances => 5
          },
          {
            :type => "winxp",
            :instances => 10,
            :ie_version => "6",
            :gold_image => "file:///var/local/images/dev-sxp-gold.img"
          },
          {
            :type => "win7",
            :instances => 10,
            :ie_version => "9",
            :gold_image => "http://iso.youdevise.com/gold/win7-ie9-gold.img"
          }
        ]
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "segrid"
    end

    env "qa", :primary_site => "space" do
      instantiate_stack "qatestmachines"
    end
  end

  it_stack("contains an environment on every node in the tree") do |root|
    root.accept do |node|
      expect(node.environment).not_to eql(nil)
    end
  end

  it_stack("does not create a hub when you do not define one") do |root|
    expect(root.find('qa-hub-001.mgmt.space.net.local')).to be_nil
  end

  it_stack("should contain the correct nodes") do |stack|
    expect(stack).to have_hosts([
      'e1-a-browser-001.mgmt.space.net.local',
      'e1-a-browser-002.mgmt.space.net.local',
      'e1-a-browser-003.mgmt.space.net.local',
      'e1-a-browser-004.mgmt.space.net.local',
      'e1-a-browser-005.mgmt.space.net.local',
      'e1-a-ie10-001.mgmt.space.net.local',
      'e1-a-ie6-001.mgmt.space.net.local',
      'e1-a-ie6-002.mgmt.space.net.local',
      'e1-a-ie9-001.mgmt.space.net.local',
      'e1-a-ie9-002.mgmt.space.net.local',
      'e1-hub-001.mgmt.space.net.local',
      'qa-a-browser-001.mgmt.space.net.local',
      'qa-a-browser-002.mgmt.space.net.local',
      'qa-a-browser-003.mgmt.space.net.local',
      'qa-a-browser-004.mgmt.space.net.local',
      'qa-a-browser-005.mgmt.space.net.local',
      'qa-a-ie6-001.mgmt.space.net.local',
      'qa-a-ie6-002.mgmt.space.net.local',
      'qa-a-ie6-003.mgmt.space.net.local',
      'qa-a-ie6-004.mgmt.space.net.local',
      'qa-a-ie6-005.mgmt.space.net.local',
      'qa-a-ie6-006.mgmt.space.net.local',
      'qa-a-ie6-007.mgmt.space.net.local',
      'qa-a-ie6-008.mgmt.space.net.local',
      'qa-a-ie6-009.mgmt.space.net.local',
      'qa-a-ie6-010.mgmt.space.net.local',
      'qa-a-ie9-001.mgmt.space.net.local',
      'qa-a-ie9-002.mgmt.space.net.local',
      'qa-a-ie9-003.mgmt.space.net.local',
      'qa-a-ie9-004.mgmt.space.net.local',
      'qa-a-ie9-005.mgmt.space.net.local',
      'qa-a-ie9-006.mgmt.space.net.local',
      'qa-a-ie9-007.mgmt.space.net.local',
      'qa-a-ie9-008.mgmt.space.net.local',
      'qa-a-ie9-009.mgmt.space.net.local',
      'qa-a-ie9-010.mgmt.space.net.local'
    ])
  end

  host("qa-a-ie9-005.mgmt.space.net.local") do |host|
    expect(host.to_spec[:selenium_hub_host]).to be_nil
  end

  host("qa-a-ie6-005.mgmt.space.net.local") do |host|
    expect(host.to_spec[:selenium_hub_host]).to be_nil
  end

  host("qa-a-browser-005.mgmt.space.net.local") do |host|
    expect(host.to_spec[:selenium_hub_host]).to be_nil
    expect(host.to_spec[:template]).to eql("senode")
    expect(host.to_spec[:selenium_deb_version]).to eql '2.32.0'
    expect(host.to_spec[:firefox_version]).to be_nil
    expect(host.to_spec[:chrome_version]).to be_nil
    expect(host.to_spec[:storage][:/][:prepare][:options][:path]).to eql '/var/local/images/gold-precise/generic.img'
    expect(host.to_spec[:ram]).to eql('2097152')
    expect(host.to_spec[:storage][:/][:size]).to eql('5G')
    expect(host.to_spec[:storage][:/][:type]).to eql('os')
    expect(host.to_spec[:disallow_destroy]).to be_nil
    expect(host.to_spec[:allocation_tags]).to eql([])
  end

  host("e1-hub-001.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql "sehub"
    expect(host.to_spec[:ram]).to eql('2097152')
    expect(host.to_spec[:storage][:/][:size]).to eql('5G')
    expect(host.to_spec[:storage][:/][:type]).to eql('os')
    expect(host.to_spec[:disallow_destroy]).to be_nil
    expect(host.to_spec[:allocation_tags]).to eql([])
    expect(host.to_spec[:selenium_deb_version]).to eql('2.41.0')
    expect(host.to_spec[:nodes]).to eql([
      'e1-a-browser-001',
      'e1-a-browser-002',
      'e1-a-browser-003',
      'e1-a-browser-004',
      'e1-a-browser-005',
      'e1-a-ie10-001',
      'e1-a-ie6-001',
      'e1-a-ie6-002',
      'e1-a-ie9-001',
      'e1-a-ie9-002'
    ])
  end

  host("e1-a-ie6-002.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("xpboot")
    expect(host.to_spec[:gold_image_url]).to eql 'file:///var/local/images/dev-sxp-gold.img'
    expect(host.to_spec[:kvm_template]).to eql 'kvm_no_virtio'
    expect(host.to_spec[:selenium_hub_host]).to eql 'e1-hub-001.mgmt.space.net.local'
    expect(host.to_spec[:selenium_version]).to eql '2.41.0'
    expect(host.to_spec[:ie_version]).to eql '6'
    expect(host.to_spec[:disallow_destroy]).to be_nil
    expect(host.to_spec[:ram]).to eql('2097152')
    expect(host.to_spec[:allocation_tags]).to eql([])
  end

  host("e1-a-ie9-002.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("win7boot")
    expect(host.to_spec[:gold_image_url]).to eql 'http://iso.youdevise.com/gold/win7-ie9-gold.img'
    expect(host.to_spec[:selenium_hub_host]).to eql 'e1-hub-001.mgmt.space.net.local'
    expect(host.to_spec[:selenium_version]).to eql '2.41.0'
    expect(host.to_spec[:ie_version]).to eql '9'
    expect(host.to_spec[:disallow_destroy]).to be_nil
    expect(host.to_spec[:ram]).to eql('2097152')
    expect(host.to_spec[:allocation_tags]).to eql([])
  end

  host("e1-a-ie10-001.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("win7boot")
    expect(host.to_spec[:gold_image_url]).to eql 'http://iso.youdevise.com/gold/win7-ie10-gold.img'
    expect(host.to_spec[:selenium_hub_host]).to eql 'e1-hub-001.mgmt.space.net.local'
    expect(host.to_spec[:selenium_version]).to eql '2.41.0'
    expect(host.to_spec[:ie_version]).to eql '10'
  end

  host("e1-a-browser-001.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("senode_trusty")
    expect(host.to_spec[:selenium_hub_host]).to eql 'e1-hub-001.mgmt.space.net.local'
    expect(host.to_spec[:selenium_deb_version]).to eql '2.41.0'
    expect(host.to_spec[:firefox_version]).to eql '36.0+build2-0ubuntu0.12.04.5'
    expect(host.to_spec[:storage][:/][:prepare][:options][:path]).to eql '/var/local/images/ubuntu-trusty.img'
    expect(host.to_spec[:chrome_version]).to eql '12.4+banana'
    expect(host.to_spec[:ram]).to eql('2097152')
    expect(host.to_spec[:storage][:/][:size]).to eql('5G')
    expect(host.to_spec[:storage][:/][:type]).to eql('os')
    expect(host.to_spec[:disallow_destroy]).to be_nil
    expect(host.to_spec[:allocation_tags]).to eql([])
  end
end
