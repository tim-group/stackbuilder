require 'stacks/test_framework'

describe_stack 'storage' do
  given do
    stack 'demo' do
      standalone_appserver 'demoapp' do
        each_machine do |machine|
          machine.image_size = '99G'
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-demoapp-002.mgmt.space.net.local") do |host|
    #pp host.to_specs.first
    host.to_specs.first[:storage].should eql(
      {
        :/ => "99G"
      }
    )
  end
end
