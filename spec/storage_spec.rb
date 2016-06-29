require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should default root storage size to 3G' do
  given do
    stack 'demo' do
      loadbalancer_service
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-lb-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/'.to_sym][:size]).to eql('3G')
  end
end

describe_stack 'should default appserver storage size to 5G' do
  given do
    stack 'demo' do
      standalone_app_service 'default'
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-default-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/'.to_sym][:size]).to eql('5G')
  end
end

describe_stack 'can specify app server system storage size' do
  given do
    stack 'demo' do
      standalone_app_service 'default' do
        each_machine do |machine|
          machine.modify_storage('/' => { :size => '10G' })
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-default-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/'.to_sym][:size]).to eql('10G')
  end
end

describe_stack 'allow additional storage to be specified' do
  given do
    stack 'demo' do
      standalone_app_service 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage('/var/lib/mysql' => { :type => 'data', :size => '50G' })
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:type]).to eql('data')
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:size]).to eql('50G')
  end
end

describe_stack 'allow all existing storage options to be modified' do
  given do
    stack 'demo' do
      standalone_app_service 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage('/'              => {
                                   :type => 'wizzy',
                                   :size => '5G',
                                   :prepare => {
                                     :method => 'image',
                                     :options => {
                                       :path => '/var/local/images/gold/duck.img'
                                     }
                                   }
                                 },
                                 '/var/lib/mysql' => {
                                   :type => 'data',
                                   :size => '500G',
                                   :prepare => {
                                     :method => 'format',
                                     :options => {
                                       :type => 'ext4'
                                     }
                                   }
                                 })
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/'.to_sym][:type]).to eql('wizzy')
    expect(host.to_specs.first[:storage]['/'.to_sym][:size]).to eql('5G')
    expect(host.to_specs.first[:storage]['/'.to_sym][:prepare][:method]).to eql('image')
    expect(host.to_specs.first[:storage]['/'.to_sym][:prepare][:options][:path]).
      to eql '/var/local/images/gold/duck.img'
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:type]).to eql('data')
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:size]).to eql('500G')
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:prepare][:method]).to eql('format')
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:prepare][:options][:type]).to eql 'ext4'
  end
end

describe_stack 'allow persistence to be set' do
  given do
    stack 'demo' do
      standalone_app_service 'mysqldb' do
        each_machine do |machine|
          machine.modify_storage('/var/lib/mysql' => {
                                   :type       => 'data',
                                   :size       => '500G',
                                   :persistent => true
                                 })
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "demo"
    end
  end

  host("e1-mysqldb-002.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:storage]['/var/lib/mysql'.to_sym][:persistent]).to eql(true)
  end
end
