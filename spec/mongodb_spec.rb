require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "mongo" do
      mongodb "mongodb" do
        self.database_name  = 'myapp'
      end
    end
    env "e1", :primary_site => "space", :secondary_site => 'moon'  do
      instantiate_stack "mongo"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-mongodb-001.mgmt.space.net.local',
        'e1-mongodb-002.mgmt.space.net.local',
        'e1-mongodbarbiter-001.mgmt.space.net.local',
        'e1-mongodbbackup-001.mgmt.moon.net.local'
      ])
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['database_name']).to eql("myapp")
  end
  host("e1-mongodbbackup-001.mgmt.moon.net.local") do |host|
    expect(host.to_enc['mongodb::backup']).to eql('ensure' => 'present')
  end
end

describe_stack 'mongodb with dependencies' do
  given do
    stack 'test' do
      virtual_appserver 'exampleapp' do
        self.application = 'example'
        depend_on "mongodb", environment.name, 'magic'
      end
      mongodb "mongodb" do
        self.database_name = 'myapp'
        self.master_instances = 2
        self.arbiter_instances = 1
        self.backup_instances = 1
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack 'test'
    end
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['dependant_instances']).to include(
      'e1-exampleapp-001.space.net.local',
      'e1-exampleapp-002.space.net.local',
      'e1-mongodb-002.space.net.local')
    expect(host.to_enc['role::mongodb_server']['dependant_instances']).not_to include(
      'e1-mongodb-001.space.net.local')
  end

  host("e1-exampleapp-001.mgmt.space.net.local") do |host|
    dependencies = host.to_enc['role::http_app']['dependencies']
    expect(dependencies['magic.mongodb.enabled']).to eql('true')
    expect(dependencies['magic.mongodb.server_fqdns']).to \
      eql('e1-mongodb-001.space.net.local,e1-mongodb-002.space.net.local')
    expect(dependencies['magic.mongodb.username']).to eql('example')
    expect(dependencies['magic.mongodb.password_hiera_key']).to eql('enc/e1/example/mongodb_magic_password')
  end
end
