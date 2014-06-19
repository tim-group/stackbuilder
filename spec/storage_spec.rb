require 'stacks/test_framework'

describe_stack 'storage' do
  given do
    stack 'demo' do
      standalone_appserver 'large' do
        each_machine do |machine|
          machine.image_size = '99G'
        end
      end
      standalone_appserver 'default' do
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-large-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage].should eql(
      {
        '/'.to_sym =>  {
         :type => 'os',
         :size => '99G'
        }
      }
    )
  end

  host("e1-default-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage].should eql(
      {
        '/'.to_sym =>  {
         :type => 'os',
         :size => '3G'
        }
      }
    )
  end

end
