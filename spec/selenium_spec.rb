require 'stacks/test_framework'
describe_stack 'selenium' do
  given do
    stack "segrid" do
      selenium_version = "2.41.0"
      hub = selenium_hub('hub-001', :selenium_version => selenium_version)
      selenium_node_cluster "a" do
        self.hub = hub
        self.selenium_version = selenium_version
        self.firefox_version = "36.0+build2-0ubuntu0.12.04.5"
        self.nodespecs = [
          { :type => "ubuntu", :instances => 5 },
          { :type => "winxp",  :instances => 2,  :ie_version => "6",  :gold_image => "file:///var/local/images/dev-sxp-gold.img" },
          { :type => "win7",   :instances => 2,  :ie_version => "9",  :gold_image => "http://iso.youdevise.com/gold/win7-ie9-gold.img" },
          { :type => "win7",   :instances => 1,  :ie_version => "10", :gold_image => "http://iso.youdevise.com/gold/win7-ie10-gold.img" }
        ]
      end
    end

    stack "qatestmachines" do
      selenium_node_cluster "a" do
        self.nodespecs = [
          { :type => "ubuntu", :instances => 5 },
          { :type => "winxp",  :instances => 10,  :ie_version => "6",  :gold_image => "file:///var/local/images/dev-sxp-gold.img" },
          { :type => "win7",   :instances => 10,  :ie_version => "9",  :gold_image => "http://iso.youdevise.com/gold/win7-ie9-gold.img" }
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

  model("contains an environment on every node in the tree") do |root|
    root.accept do |node|
      node.environment.should_not eql(nil)
    end
  end

  model("does not create a hub when you do not define one") do |root|
    root.find('qa-hub-001.mgmt.space.net.local').should be_nil
  end

  host("qa-a-ie9-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil
  end

  host("qa-a-ie6-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil
  end

  host("qa-a-browser-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil
  end

  host("e1-hub-001.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql "sehub"
    host.to_spec[:selenium_version].should eql('2.41.0')
    host.to_spec[:nodes].should eql([
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
    host.to_spec[:template].should eql("xpboot")
    host.to_spec[:gold_image_url].should eql 'file:///var/local/images/dev-sxp-gold.img'
    host.to_spec[:kvm_template].should eql 'kvm_no_virtio'
    host.to_spec[:selenium_hub_host].should eql 'e1-hub-001.mgmt.space.net.local'
    host.to_spec[:selenium_version].should eql '2.41.0'
    host.to_spec[:ie_version].should eql '6'
  end

  host("e1-a-ie9-002.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("win7boot")
    host.to_spec[:gold_image_url].should eql 'http://iso.youdevise.com/gold/win7-ie9-gold.img'
    host.to_spec[:selenium_hub_host].should eql 'e1-hub-001.mgmt.space.net.local'
    host.to_spec[:selenium_version].should eql '2.41.0'
    host.to_spec[:ie_version].should eql '9'
  end

  host("e1-a-ie10-001.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("win7boot")
    host.to_spec[:gold_image_url].should eql 'http://iso.youdevise.com/gold/win7-ie10-gold.img'
    host.to_spec[:selenium_hub_host].should eql 'e1-hub-001.mgmt.space.net.local'
    host.to_spec[:selenium_version].should eql '2.41.0'
    host.to_spec[:ie_version].should eql '10'
  end

  host("e1-a-browser-001.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("senode")
    host.to_spec[:selenium_hub_host].should eql 'e1-hub-001.mgmt.space.net.local'
    host.to_spec[:selenium_version].should eql '2.41.0'
    host.to_spec[:firefox_version].should eql '36.0+build2-0ubuntu0.12.04.5'
  end
end
