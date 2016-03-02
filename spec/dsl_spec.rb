require 'stackbuilder/stacks/factory'

describe Stacks::DSL do
  before do
    extend Stacks::DSL
    stack "blah" do
      virtual_appserver "appx"
      virtual_appserver "dbx"
    end
    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end
  end

  it 'binds to configuration from the environment' do
    appx = environments["ci"]["blah"]["appx"]
    expect(appx.to_specs.size).to eql 2
    spec = find("ci-appx-001.mgmt.st.net.local").to_spec
    expect(spec[:hostname]).to eql('ci-appx-001')
    expect(spec[:domain]).to eql('st.net.local')
    expect(spec[:fabric]).to eql('st')
    expect(spec[:availability_group]).to eql('ci-appx')
    expect(spec[:qualified_hostnames]).
      to eql(:mgmt => "ci-appx-001.mgmt.st.net.local", :prod => "ci-appx-001.st.net.local")
  end

  it 'can make an arbitrary specd machine' do
    stack "fabric" do
      @definitions["puppetmaster"] = Stacks::Services::StandaloneServer.new("puppetmaster-001") do
        def to_specs
          specs = super
          specs.each do |spec|
            spec[:bling] = true
          end
          specs
        end
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
    end

    spec = environments["ci"]["fabric"].to_specs.first
    expect(spec[:bling]).to eql(true)
  end

  it 'can find sub environments' do
    env "parent", :primary_site => "st", :secondary_site => "bs" do
      env "sub" do
      end
    end

    expect(find_environment("sub").name).to eql("sub")
    expect(find_environment("parent").name).to eql("parent")
  end

  it 'spec always provides logicalenv' do
    stack "app" do
      virtual_appserver "appx"
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "app"
    end

    spec = find("ci-appx-001.mgmt.st.net.local").to_spec
    expect(spec[:logicalenv]).to eql('ci')
  end
end
