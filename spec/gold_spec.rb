require 'stacks/test_framework'
describe_stack 'gold image' do
  given do
    stack "gold-image" do
      gold 'goldimage' do
        ubuntu 'precise'
        ubuntu 'trusty'
        win 'xp', 'ie7',
          :master_location => 'http://imageserver.net.local/master/precise/'
        win 'win7', 'ie9',
          :master_location => 'http://imageserver.net.local/master/precise/'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "gold-image"
    end
  end

  model("contains an environment on every node in the tree") do |root|
    root.accept do |node|
      node.environment.should_not eql(nil)
    end
  end

  host("e1-ubuntu-precise-gold.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("ubuntu-precise")
    host.to_spec[:hostname].should eql("e1-ubuntu-precise-gold")
    host.to_spec[:dont_start].should eql(true)
    host.to_spec[:storage][:/][:prepare][:options][:shrink_after_unmount].should eql(true)
    host.to_spec[:storage][:/][:prepare][:options][:resize].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab].should eql(false)
  end
  host("e1-ubuntu-trusty-gold.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("ubuntu-trusty")
    host.to_spec[:hostname].should eql("e1-ubuntu-trusty-gold")
    host.to_spec[:dont_start].should eql(true)
    host.to_spec[:storage][:/][:prepare][:options][:shrink_after_unmount].should eql(true)
    host.to_spec[:storage][:/][:prepare][:options][:resize].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab].should eql(false)
  end

  host("e1-xp-ie7-gold.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("xpgold")
    host.to_spec[:hostname].should eql("e1-xp-ie7-gold")
    host.to_spec[:storage][:/][:size].should eql('8G')
    host.to_spec[:storage][:/][:prepare][:options][:virtio].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:resize].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:path].should eql('http://imageserver.net.local/master/precise/xp-ie7-master.img')
  end

  host("e1-win7-ie9-gold.mgmt.space.net.local") do |host|
    host.to_spec[:template].should eql("win7gold")
    host.to_spec[:hostname].should eql("e1-win7-ie9-gold")
    host.to_spec[:storage][:/][:size].should eql('15G')
    host.to_spec[:storage][:/][:prepare][:options][:resize].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab].should eql(false)
    host.to_spec[:storage][:/][:prepare][:options][:path].should eql('http://imageserver.net.local/master/precise/win7-ie9-master.img')
  end
end
