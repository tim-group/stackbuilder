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
    host.to_enc['role::mongodb_server']['application'].should eql("myapp")
    host.to_enc['mongodb::users']['environment'].should eql('e1')
  end

  host("latest-mongodb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mongodb_server']['application'].should eql("myapp")
    host.to_enc['mongodb::users']['environment'].should eql('latest')
  end

  host("latest-mongodbarbiter-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mongodb_server']['application'].should eql("myapp")
    host.to_enc['mongodb::users']['environment'].should eql('latest')
  end

  host("prodbackup-mongodb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mongodb_server']['application'].should eql("myapp")
    host.to_enc['mongodb::backup'].should eql('ensure' => 'present')
    host.to_enc['mongodb::users']['environment'].should eql('prodbackup')
  end
end
