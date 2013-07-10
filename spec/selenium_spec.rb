require 'stacks/test_framework'
describe_stack 'selenium' do
  given do
    stack "segrid" do
      segrid :v=>2 do
        winxp "6", :instances=>10,
          :gold_image=> "file:///var/local/images/dev-sxp-gold.img",
          :se_version=>"2.32.0"
        ubuntu :instances=>5
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "segrid"
    end
  end

  host("") do |host|
  end

  host("e1-hub-001.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      { :fabric=>"space",
        :template=>"sehub",
        :qualified_hostnames=>
        {:mgmt=>"e1-hub-001.mgmt.space.net.local"},
          :group=>nil,
          :networks=>[:mgmt],
          :hostname=>"e1-hub-001",
          :ram=>"2097152",
          :domain=>"space.net.local"})
  end

  host("e1-xp6-005.mgmt.space.net.local") do |host|
    host.to_spec.should eql(
      {  :fabric=>"space",
        :template=>"xpboot",
        :se_hub => 'e1-hub-001.mgmt.space.net.local',
        :se_version =>  '2.32.0',
        :gold_image_url => 'file:///var/local/images/dev-sxp-gold.img',
        :launch_script => 'start-grid.bat',
        :qualified_hostnames=>
        {:mgmt=>"e1-xp6-005.mgmt.space.net.local"},
          :group=>nil,
          :networks=>[:mgmt],
          :hostname=>"e1-xp6-005",
          :ram=>"2097152",
          :domain=>"space.net.local"})
  end

  host("e1-browser-001.mgmt.space.net.local") do |host|
    host.to_spec.should eql({
      :fabric=>"space",
      :template=>"senode",
      :se_hub => 'e1-hub-001.mgmt.space.net.local',
      :se_version =>  '2.32.0',
      :qualified_hostnames=>
      {:mgmt=>"e1-browser-001.mgmt.space.net.local"},
        :group=>nil,
        :networks=>[:mgmt],
        :hostname=>"e1-browser-001",
        :ram=>"2097152",
        :domain=>"space.net.local"})
  end

end
