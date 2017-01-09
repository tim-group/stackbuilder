require 'stackbuilder/stacks/factory'
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

  it_stack("contains an environment on every node in the tree") do |root|
    root.accept do |node|
      expect(node.environment).not_to eql(nil)
    end
  end

  it_stack("should contain the correct nodes") do |stack|
    expect(stack).to have_hosts(['e1-ubuntu-precise-gold.mgmt.space.net.local','e1-ubuntu-trusty-gold.mgmt.space.net.local','e1-win7-ie9-gold.mgmt.space.net.local','e1-xp-ie7-gold.mgmt.space.net.local'])
  end

  host("e1-ubuntu-precise-gold.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("ubuntu-precise")
    expect(host.to_spec[:hostname]).to eql("e1-ubuntu-precise-gold")
    expect(host.to_spec[:dont_start]).to eql(true)
    expect(host.to_spec[:storage][:/][:prepare][:options][:shrink_after_unmount]).to eql(true)
    expect(host.to_spec[:storage][:/][:prepare][:options][:resize]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab]).to eql(false)
  end
  host("e1-ubuntu-trusty-gold.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("ubuntu-trusty")
    expect(host.to_spec[:hostname]).to eql("e1-ubuntu-trusty-gold")
    expect(host.to_spec[:dont_start]).to eql(true)
    expect(host.to_spec[:storage][:/][:prepare][:options][:shrink_after_unmount]).to eql(true)
    expect(host.to_spec[:storage][:/][:prepare][:options][:resize]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab]).to eql(false)
  end

  host("e1-xp-ie7-gold.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("xpgold")
    expect(host.to_spec[:hostname]).to eql("e1-xp-ie7-gold")
    expect(host.to_spec[:storage][:/][:size]).to eql('8G')
    expect(host.to_spec[:storage][:/][:prepare][:options][:virtio]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:resize]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:path]).to eql('http://imageserver.net.local/master/precise/xp-ie7-master.img')
  end

  host("e1-win7-ie9-gold.mgmt.space.net.local") do |host|
    expect(host.to_spec[:template]).to eql("win7gold")
    expect(host.to_spec[:hostname]).to eql("e1-win7-ie9-gold")
    expect(host.to_spec[:storage][:/][:size]).to eql('15G')
    expect(host.to_spec[:storage][:/][:prepare][:options][:resize]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:create_in_fstab]).to eql(false)
    expect(host.to_spec[:storage][:/][:prepare][:options][:path]).to eql('http://imageserver.net.local/master/precise/win7-ie9-master.img')
  end
end
