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
    host.to_specs.first[:storage].should eql({
      '/'.to_sym =>  {
        :type       => 'os',
        :size       => '3G',
        :persistent => false,
        :prepare    => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      }
    })
  end
end

describe_stack 'override root storage size when image_size is set' do
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
    host.to_specs.first[:storage].should eql({
      '/'.to_sym =>  {
        :type       => 'os',
        :size       => '99G',
        :persistent => false,
        :prepare => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      }
    })
  end
end

describe_stack 'allow override the gold image location' do
  given do
    stack 'demo' do
      standalone_appserver 'override' do
        each_machine do |machine|
          machine.modify_storage({
            '/' => {
              :prepare => {
                :options => {
                  :path => '/tmp/goldielocks.img'
                },
              },
            }
          })
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-override-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage].should eql({
      '/'.to_sym =>  {
        :type       => 'os',
        :size       => '3G',
        :persistent => false,
        :prepare => {
          :method => 'image',
          :options => {
            :path => '/tmp/goldielocks.img'
          },
        },
      }
    })
  end
end

describe_stack 'allow override the method' do
  given do
    stack 'demo' do
      standalone_appserver 'override' do
        each_machine do |machine|
          machine.modify_storage({
            '/' => {
              :prepare => {
                :method => 'format',
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

  host("e1-override-002.mgmt.space.net.local") do |host|
    host.to_specs.first[:storage].should eql({
      '/'.to_sym =>  {
        :type       => 'os',
        :size       => '3G',
        :persistent => false,
        :prepare    => {
          :method => 'format',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      }
    })
  end
end


describe_stack 'allow additional storage to be provided' do
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
    host.to_specs.first[:storage].should eql({
      '/'.to_sym =>  {
        :type       => 'os',
        :size       => '3G',
        :persistent => false,
        :prepare    => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      },
      '/var/lib/mysql'.to_sym =>  { :type => 'data', :size => '50G' },
    })
  end
end

describe_stack 'allow existing storage to be modified' do
  given do
    stack 'demo' do
      standalone_appserver 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage({
            '/'              => {
              :prepare => {
                :method => 'image',
                :options => {
                  :path => '/var/local/images/gold/generic.img'
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
    host.to_specs.first[:storage].should eql({
      '/'.to_sym              =>  {
        :type       => 'os',
        :size       => '3G',
        :persistent => false,
        :prepare => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold/generic.img'
          },
        },
      },
      '/var/lib/mysql'.to_sym =>  {
        :type       => 'data',
        :size       => '500G',
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
