require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "mongo" do
      mongodb "mongodb" do
        self.application = 'myapp'
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "mongo"
    end
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::mongodb_server' => {
        'application' => "myapp",
        'arbiter'     => false
      }})
  end
end
