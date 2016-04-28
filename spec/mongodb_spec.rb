require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "mongo" do
      mongodb "mongodb" do
        self.application = 'myapp'
      end
    end

    stack "mongo_backup" do
      mongodb "mongodb" do
        self.application = 'myapp'
        each_machine do |machine|
          machine.backup = true
        end
      end
    end

    stack "mongo_arbiter" do
      mongodb "mongodbarbiter" do
        self.application = 'myapp'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mongo"
    end

    env "latest", :primary_site => "space" do
      instantiate_stack "mongo"
      instantiate_stack "mongo_arbiter"
    end
    env "prodbackup", :primary_site => "space" do
      instantiate_stack "mongo_backup"
    end
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['application']).to eql("myapp")
  end

  host("latest-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['application']).to eql("myapp")
  end

  host("latest-mongodbarbiter-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['application']).to eql("myapp")
  end

  host("prodbackup-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['application']).to eql("myapp")
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
        self.application = 'myapp'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack 'test'
    end
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mongodb_server']['dependant_instances']).to \
      eql(['e1-exampleapp-001.space.net.local', 'e1-exampleapp-002.space.net.local'])
  end

  host("e1-exampleapp-001.mgmt.space.net.local") do |host|
    dependencies = host.to_enc['role::http_app']['dependencies']
    pp dependencies
    expect(dependencies['magic.mongodb.enabled']).to eql('true')
    expect(dependencies['magic.mongodb.server_fqdns']).to \
      eql('e1-mongodb-001.space.net.local,e1-mongodb-002.space.net.local')
    expect(dependencies['magic.mongodb.username']).to eql('example')
    expect(dependencies['magic.mongodb.password_hiera_key']).to eql('enc/e1/example/mongodb_magic_password')
  end
end
