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
      '/'.to_sym =>  { :type => 'os', :size => '3G' }
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
      '/'.to_sym =>  { :type => 'os', :size => '99G' }
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
      '/'.to_sym              =>  { :type => 'os', :size => '3G' },
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
            '/'              => { :size => '90G' },
            '/var/lib/mysql' => { :type => 'data', :size => '500G' },
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
      '/'.to_sym              =>  { :type => 'os', :size => '90G' },
      '/var/lib/mysql'.to_sym =>  { :type => 'data', :size => '500G' },
    })
  end
end

describe_stack 'raise exception if un-supported storage type is requested' do
  given do
    stack 'demo' do
      standalone_appserver 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage({
            '/var/lib/mysql' => { :type => 'infinidisk', :size => '50G' },
          })
        end
      end
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    expect {
      host.to_specs.first[:storage]
    }.to raise_error 'infinidisk is not a supported storage type, supported types: os, data'
  end
end
