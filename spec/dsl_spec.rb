require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'stacks/standalone_server'
require 'pp'

describe Stacks::DSL do

  before do
    extend Stacks::DSL
    stack "blah" do
      virtual_appserver "appx"
      virtual_appserver "dbx"
    end
    env "ci", :primary_site=>"st", :secondary_site=>"bs" do
      instantiate_stack "blah"
    end
  end

  it 'binds to configuration from the environment' do
    appx = environments["ci"]["blah"]["appx"]
    appx.to_specs.size.should eql 2
    appx.to_specs.shift[:hostname].should eql('ci-appx-001')
    appx.to_specs.shift[:domain].should eql('st.net.local')
    appx.to_specs.shift[:fabric].should eql('st')
    appx.to_specs.shift[:availability_group].should eql('ci-appx')
    appx.to_specs.shift[:qualified_hostnames].should eql({:mgmt => "ci-appx-001.mgmt.st.net.local", :prod => "ci-appx-001.st.net.local"})
  end

  it 'can make an arbitrary specd machine' do
    stack "fabric" do
      @definitions["puppetmaster"] = Stacks::StandaloneServer.new("puppetmaster-001", :primary_site) do
        def to_specs
          specs = super
          specs.each do |spec|
            spec[:bling] = true
          end
          return specs
        end
      end
    end

    env "ci", :primary_site=>"st", :secondary_site=>"bs" do
      instantiate_stack "fabric"
    end

    environments["ci"]["fabric"].to_specs.should eql([{
      :hostname => "ci-puppetmaster-001",
      :bling => true,
      :domain => "st.net.local",
      :qualified_hostnames => {:mgmt => "ci-puppetmaster-001.mgmt.st.net.local", :prod => "ci-puppetmaster-001.st.net.local"},
      :networks => [:mgmt, :prod],
      :fabric => "st",
      :ram=>"2097152",
      :storage=>{
        :/ => {
          :type=>"os",
          :size=>"3G",
          :prepare=>{
            :method=>"image",
            :options=>{
              :path=>"/var/local/images/gold-precise/generic.img"
            }
          }
        }
      }
    }])
  end

  it 'can find sub environments' do
    env "parent", :primary_site=>"st", :secondary_site=>"bs" do
      env "sub" do
      end
    end

    find_environment("sub").name.should eql("sub")
    find_environment("parent").name.should eql("parent")
  end
end
