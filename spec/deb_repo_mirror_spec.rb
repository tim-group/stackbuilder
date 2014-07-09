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

    host.to_specs.shift[:cnames].should eql({
      :mgmt => {'deb-transitional' => 'e1-debrepomirror-001.mgmt.space.net.local'}
    })

  end
end

describe_stack 'debrepomirror without cname' do
  given do
    stack "debrepomirror" do
      debrepo_mirror "debrepomirror" do
        each_machine do |machine|
          machine.cnames = {}
        end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "debrepomirror"
    end
  end

  host("e1-debrepomirror-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:cnames].should eql({})
  end
end
