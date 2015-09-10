require 'stackbuilder/stacks/factory'
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
    expect(e.domain('st')).to eql('st.net.local')
    expect(e.domain('st', :prod)).to eql('st.net.local')
    expect(e.domain('st', :mgmt)).to eql('mgmt.st.net.local')
    expect(e.domain('st', :front)).to eql('front.st.net.local')
    expect(e.children.size).to eql(1)
    expect(e.contains_node_of_type?(Stacks::Services::AppService)).to eql(true)

    host('e-appx-001.mgmt.st.net.local') do |host|
      expect(e.children.first).to eql(host)
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
    expect(daddy.sub_environments.size).to eql(2)
    expect(daddy.sub_environment_names.size).to eql(daddy.sub_environments.size)
    expect(daddy.sub_environment_names).to include('daughter', 'son')

    environment('daughter') do |daughter|
      expect(daddy.child?(daughter)).to eql(true)
      expect(daddy.child_or_self?(daughter)).to eql(true)
      expect(daddy.child_or_self?(daddy)).to eql(true)
    end

    environment('latest') do |latest|
      expect(daddy.child_or_self?(latest)).to eql(false)
    end
  end

  environment('daughter', 'should know about its parent environment') do |daughter|
    environment('daddy') do |daddy|
      expect(daughter.parent).to eql(daddy)
      expect(daugther.parent?).to eql(true)
      expect(daughter.sub_environments).to eql([])
    end
  end

  environment('latest', 'should standalone') do |latest|
    expect(latest.parent).to be_nil
    expect(latest.parent?).to eql(false)
    expect(latest.sub_environments).to eql([])
  end
end
