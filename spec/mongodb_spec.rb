require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "mongo" do
      mongodb "mongodb" do
        each_machine do |machine|
          machine.mongosecret = "myapp"
        end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "mongo"
    end
  end

  host("e1-mongodb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::mongodb_server' => {
        'mongosecret' => "myapp"
      }})
  end
end
