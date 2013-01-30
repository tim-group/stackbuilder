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
  end

  it 'binds to configuration from the environment' do
    bind_to('ci')
    appx = stacks["blah"]["appx"]
    appx.to_specs.should eql([{
      :hostname => "ci-appx-001",
      :domain => "st.net.local",
      :fabric => "st",
      :group => "ci-appx",
      :networks => ["mgmt","prod"],
      :qualified_hostnames => {"mgmt"=>"ci-appx-001.mgmt.st.net.local", "prod"=>"ci-appx-001.st.net.local"}
      },
      {
      :hostname => "ci-appx-002",
      :domain => "st.net.local",
      :fabric => "st",
      :group => "ci-appx",
      :networks => ["mgmt","prod"],
      :qualified_hostnames => {"mgmt"=>"ci-appx-002.mgmt.st.net.local", "prod"=>"ci-appx-002.st.net.local"}
      }])
  end

  it 'can make an arbitrary specd machine' do
    stack "fabric" do
      @definitions["puppetmaster"] = Stacks::Server.new("puppetmaster","001", :primary) do
        def to_specs
          specs = super
          specs.each do |spec|
            spec[:bling] = true
          end
          return specs
        end
      end
    end
    bind_to('ci')
    pp stacks["fabric"].to_specs
    stacks["fabric"].to_specs.should eql([{
      :hostname => "ci-puppetmaster-001",
      :bling => true,
      :group => "ci-puppetmaster",
      :domain => "st.net.local",
      :qualified_hostnames => {
          "prod" => "ci-puppetmaster-001.st.net.local",
          "mgmt" => "ci-puppetmaster-001.mgmt.st.net.local"},
      :networks => ["mgmt", "prod"],
      :fabric => "st"
    }])
  end

end
