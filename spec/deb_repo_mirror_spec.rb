require 'stacks/test_framework'

describe_stack 'debrepomirror' do
  given do
    stack "debrepomirror" do
      debrepo_mirror "debrepomirror" do
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "debrepomirror"
    end
  end

  host("e1-debrepomirror-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::deb_repo_mirror' => {}
    })

    host.to_specs.should eql([
     {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-debrepomirror-001.mgmt.space.net.local",
          :prod=>"e1-debrepomirror-001.space.net.local"},
        :availability_group=>"e1-debrepomirror",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-debrepomirror-001",
        :ram=>"2097152",
        :cnames => {:mgmt => {'deb-transitional' => 'e1-debrepomirror-001.mgmt.space.net.local'}},
        :domain=>"space.net.local"}])

  end
end
