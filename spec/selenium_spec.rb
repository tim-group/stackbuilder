require 'stacks/test_framework'
describe_stack 'selenium' do
  given do
    stack "segrid" do
      segrid :v => 2 do
        hub :selenium_version => "2.41.0"
        winxp "6", :instances => 2,
                   :gold_image=> "file:///var/local/images/dev-sxp-gold.img",
                   :selenium_version => "2.41.0",
                   :ie_version => "6"
        win7 "9", :instances => 2,
                  :gold_image=> "http://iso.youdevise.com/gold/win7-ie9-gold.img",
                  :selenium_version => "2.39.0",
                  :ie_version => "9"
        win "win7", :instances => 1,
                    :gold_image=> "http://iso.youdevise.com/gold/win7-ie10-gold.img",
                    :selenium_version => "2.39.0",
                    :ie_version => "10"
        ubuntu :instances => 5,
               :selenium_version => "2.32.0"
      end
    end

    stack "qatestmachines" do
      segrid :v => 2 do
        winxp "6", :instances => 10,
                   :gold_image=> "file:///var/local/images/dev-sxp-gold.img",
                   :selenium_version => "2.32.0"
        win7 "9", :instances => 10,
                  :gold_image=> "http://iso.youdevise.com/gold/win7-ie9-gold.img",
                  :selenium_version => "2.32.0"
        ubuntu :instances => 5,
               :selenium_version => "2.32.0"
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
    root.find('qa-hub-001.mgmt.space.net.local').should be_nil()
  end

  host("qa-ie9-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil()
  end

  host("qa-ie6-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil()
  end

  host("qa-browser-005.mgmt.space.net.local") do |host|
    host.to_spec[:selenium_hub_host].should be_nil()
  end

  host("e1-hub-001.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      { :fabric => "space",
        :template => "sehub",
        :qualified_hostnames => { :mgmt => "e1-hub-001.mgmt.space.net.local" },
        :availability_group => nil,
        :networks => [:mgmt],
        :hostname => "e1-hub-001",
        :ram => "2097152",
        :domain => "space.net.local",
        :nodes => ["e1-browser-001",
                   "e1-browser-002",
                   "e1-browser-003",
                   "e1-browser-004",
                   "e1-browser-005",
                   "e1-ie10-001",
                   "e1-ie6-001",
                   "e1-ie6-002",
                   "e1-ie9-001",
                   "e1-ie9-002"],
        :selenium_version => "2.41.0",
        :storage => {'/'.to_sym =>{:type=>"os", :size=>"3G"}},
      }
    )
  end

  host("e1-ie6-002.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      { :fabric => "space",
        :availability_group => nil,
        :template => "xpboot",
        :kvm_template => 'kvm_no_virtio',
        :gold_image_url => 'file:///var/local/images/dev-sxp-gold.img',
        :image_size => "8G",
        :ram => "2097152",
        :networks => [:mgmt],
        :hostname => "e1-ie6-002",
        :qualified_hostnames=> { :mgmt => "e1-ie6-002.mgmt.space.net.local" },
        :domain => "space.net.local",
        :selenium_hub_host => 'e1-hub-001.mgmt.space.net.local',
        :selenium_version => "2.41.0",
        :ie_version => "6",
        :storage => {'/'.to_sym =>{:type=>"os", :prepare=>{:options=>{:create_in_fstab=>false, :path=>"file:///var/local/images/dev-sxp-gold.img", :resize=>false, :virtio=>false}}, :size=>"8G"}},
      })
  end

  host("e1-ie9-002.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      { :fabric => "space",
        :availability_group => nil,
        :template => "win7boot",
        :gold_image_url => 'http://iso.youdevise.com/gold/win7-ie9-gold.img',
        :image_size => "15G",
        :ram => "2097152",
        :networks => [:mgmt],
        :hostname => "e1-ie9-002",
        :qualified_hostnames=> { :mgmt => "e1-ie9-002.mgmt.space.net.local"},
        :domain => "space.net.local",
        :selenium_hub_host => 'e1-hub-001.mgmt.space.net.local',
        :selenium_version => "2.39.0",
        :ie_version => "9",
        :storage => {'/'.to_sym =>{:type=>"os", :prepare=>{:options=>{:create_in_fstab=>false, :path=>"http://iso.youdevise.com/gold/win7-ie9-gold.img", :resize=>false}}, :size=>"15G"}},
      })
  end

  host("e1-ie10-001.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      { :fabric => "space",
        :availability_group => nil,
        :template => "win7boot",
        :gold_image_url => 'http://iso.youdevise.com/gold/win7-ie10-gold.img',
        :image_size => "15G",
        :ram => "2097152",
        :networks => [:mgmt],
        :hostname => "e1-ie10-001",
        :qualified_hostnames=> { :mgmt => "e1-ie10-001.mgmt.space.net.local"},
        :domain => "space.net.local",
        :selenium_hub_host => 'e1-hub-001.mgmt.space.net.local',
        :selenium_version => "2.39.0",
        :ie_version => "10",
        :storage => {'/'.to_sym =>{:type=>"os", :prepare=>{:options=>{:create_in_fstab=>false, :path=>"http://iso.youdevise.com/gold/win7-ie10-gold.img", :resize=>false}}, :size=>"15G"}},
      })
  end

  host("e1-browser-001.mgmt.space.net.local") do |host|
    host.to_spec.should eql({
      :fabric => "space",
      :availability_group => nil,
      :template => "senode",
      :ram => "2097152",
      :networks => [:mgmt],
      :hostname => "e1-browser-001",
      :qualified_hostnames=> {:mgmt => "e1-browser-001.mgmt.space.net.local"},
      :domain => "space.net.local",
      :selenium_hub_host => 'e1-hub-001.mgmt.space.net.local',
      :selenium_version => '2.32.0',
      :storage => {'/'.to_sym =>{:type=>"os", :size=>"3G"}},
    })
  end

end
