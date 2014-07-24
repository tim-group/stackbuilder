require 'stacks/test_framework'

describe_stack 'should default root storage size to 3G' do
  given do
    stack 'demo' do
      standalone_appserver 'default'
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-default-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage]['/'.to_sym][:size].should eql('3G')
  end
end

describe_stack 'legacy override root storage size when image_size is set' do
  given do
    stack 'demo' do
      standalone_appserver 'override' do
        each_machine do |machine|
          machine.image_size = '99G'
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-override-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage]['/'.to_sym][:size].should eql('99G')
  end
end


describe_stack 'allow additional storage to be specified' do
  given do
    stack 'demo' do
      standalone_appserver 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage({
            '/var/lib/mysql' => { :type => 'data', :size => '50G' },
          })
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:type].should eql('data')
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:size].should eql('50G')
  end
end

describe_stack 'allow all existing storage options to be modified' do
  given do
    stack 'demo' do
      standalone_appserver 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage({
            '/'              => {
              :type => 'wizzy',
              :size => '5G',
              :prepare => {
                :method => 'image',
                :options => {
                  :path => '/var/local/images/gold/duck.img'
                },
              },
            },
            '/var/lib/mysql' => {
              :type => 'data',
              :size => '500G',
              :prepare => {
                 :method => 'format',
                 :options => {
                   :type => 'ext4'
                 },
              },
            },
          })
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage]['/'.to_sym][:type].should eql('wizzy')
    host.to_specs.first[:storage]['/'.to_sym][:size].should eql('5G')
    host.to_specs.first[:storage]['/'.to_sym][:prepare][:method].should eql('image')
    host.to_specs.first[:storage]['/'.to_sym][:prepare][:options][:path].should eql '/var/local/images/gold/duck.img'
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:type].should eql('data')
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:size].should eql('500G')
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:prepare][:method].should eql('format')
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:prepare][:options][:type].should eql 'ext4'
  end
end

describe_stack 'allow persistence to be set' do
  given do
    stack 'demo' do
      standalone_appserver 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage({
            '/var/lib/mysql' => {
              :type       => 'data',
              :size       => '500G',
              :persistent => true,
            },
          })
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:persistent].should eql(true)
  end
end
