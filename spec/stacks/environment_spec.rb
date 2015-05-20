require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic environment' do
  given do
    stack "x" do
      virtual_appserver "appx"
    end

    env "e", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "x"
    end
  end

  environment('e', 'should provide a working domain method') do |e|
    e.domain('st').should eql('st.net.local')
    e.domain('st', :prod).should eql('st.net.local')
    e.domain('st', :mgmt).should eql('mgmt.st.net.local')
    e.domain('st', :front).should eql('front.st.net.local')
    e.children.size.should eql(1)
    e.contains_node_of_type?(Stacks::Services::AppService).should eql(true)

    host('e-appx-001.mgmt.st.net.local') do |host|
      e.children.first.should eql(host)
    end
  end
end

describe_stack 'sub environments' do
  given do
    stack "x" do
      virtual_appserver "appx"
    end
    stack "y" do
      virtual_appserver "appy"
    end
    stack "z" do
      virtual_appserver "appz"
    end

    env "daddy", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "x"
      env "daughter" do
        instantiate_stack "y"
      end
      env "son" do
        instantiate_stack "z"
      end
    end
    env "latest", :primary_site => "st", :secondary_site => "bs"
  end

  environment('daddy', 'should have the correct sub environments') do |daddy|
    daddy.sub_environments.size.should eql(2)
    daddy.sub_environment_names.size.should eql(daddy.sub_environments.size)
    daddy.sub_environment_names.should include('daughter', 'son')

    environment('daughter') do |daughter|
      daddy.child?(daughter).should eql(true)
      daddy.child_or_self?(daughter).should eql(true)
      daddy.child_or_self?(daddy).should eql(true)
    end

    environment('latest') do |latest|
      daddy.child_or_self?(latest).should eql(false)
    end
  end

  environment('daughter', 'should know about its parent environment') do |daughter|
    environment('daddy') do |daddy|
      daughter.parent.should eql(daddy)
      daugther.parent?.should eql(true)
      daughter.sub_environments.should eql([])
    end
  end

  environment('latest', 'should standalone') do |latest|
    latest.parent.should be_nil
    latest.parent?.should eql(false)
    latest.sub_environments.should eql([])
  end
end
