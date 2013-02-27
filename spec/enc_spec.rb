require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'

describe Stacks::DSL do

  before do
    extend Stacks::DSL

    stack "fabric" do
      loadbalancer
    end

    stack "blah" do
      virtualservice "appx"
      virtualservice "dbx"
    end

    env "ci", :primary=>"st", :secondary=>"bs"

    env "st", :primary=>"st", :secondary=>"bs" do
      instantiate_stack "fabric"
      env "ci" do
        instantiate_stack "blah"
      end
      env "ci2" do
        instantiate_stack "blah"
     end
    end
    env "bla", :primary=>"st", :secondary=>"bs"
  end


  it 'can generate the load balancer spec' do
    find("st-lb-001.mgmt.st.net.local").virtual_services.size.should eql(2)
  end

  it 'binds to configuration from the environment' do
#    stacks = bind_to('ci')

    class Resolv::DNS
      def getaddress(url)
        return "1.1.1.1"
      end
    end

    enc_for("ci-appx-001.mgmt.st.net.local").should eql(
      {
      'role::http_app'=> {
      'application' => 'appx',
      'groups' => ['blue'],
      'vip' => '1.1.1.1',
      'environment' => 'ci'
    }
    }
    )

    stacks = bind_to('bla')
  end

end
