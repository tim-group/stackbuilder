require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'

describe Stacks::DSL do

  before do
    extend Stacks::DSL
    stack "blah" do
      virtualservice "appx"
      virtualservice "dbx"
    end
    env "ci", :primary=>"st", :secondary=>"bs"
    env "bla", :primary=>"st", :secondary=>"bs"
  end

  it 'binds to configuration from the environment' do
    stacks = bind_to('ci')

    enc_for("ci-appx-001.mgmt.st.net.local").should eql(
      {
        'role::http_app'=> {
          'application' => 'appx',
          'groups' => ['blue'],
          'vip' => 'ci-appx-vip.st.net.local',
          'environment' => 'ci'
        }
      }
    )

    stacks = bind_to('bla')
    pp stacks


  end

end
