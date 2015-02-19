require 'stacks/test_framework'

describe_stack 'debrepo' do
  given do
    stack "debrepo" do
      debrepo "debrepo" do
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "debrepo"
    end
  end

  host("e1-debrepo-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql('role::deb_repo' => {})

    host.to_specs.shift[:cnames].should eql(:mgmt => {
                                              'aptly-master'     => 'e1-debrepo-001.mgmt.space.net.local',
                                              'deb-transitional' => 'e1-debrepo-001.mgmt.space.net.local'
                                            })
  end
end

describe_stack 'debrepo without a cname' do
  given do
    stack "debrepo" do
      debrepo "debrepo" do
        each_machine do |machine|
          machine.cnames = {}
        end
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "debrepo"
    end
  end

  host("e1-debrepo-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:cnames].should eql({})
  end
end
