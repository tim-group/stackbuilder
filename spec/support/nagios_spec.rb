require 'stackbuilder/support/nagios'
require 'web-test-framework'

# This test is slow because of how webrick is written. To speed it up edit
# /usr/lib/ruby/1.9.1/webrick/server.rb and apply this diff:
#            begin
# -            if svrs = IO.select(@listeners, nil, nil, 2.0)
# +            if svrs = IO.select(@listeners, nil, nil, 0.01)
#                svrs[0].each{|svr|
describe Support::Nagios::Service do
  class MockService
    def schedule_downtime(_machine, _duration)
      "OK"
    end

    def cancel_downtime(_machine)
      "OK"
    end
  end

  before do
    @mock_service = MockService.new
    @test = Support::Nagios::Service.new(service: @mock_service)
    @test_machine1 = Stacks::MachineDef.new("test1")
    @test_machine2 = Stacks::MachineDef.new("test2")
    env = Stacks::Environment.new("env", { primary_site: "oy" }, nil, {}, {})
    @test_machine1.bind_to(env)
    @test_machine2.bind_to(env)
    @test_machines = [@test_machine1, @test_machine2]
  end

  it 'should schedule downtime for all machines and callback success' do
    @mock_service.should_receive(:schedule_downtime).with(@test_machine1, 1200)
    @mock_service.should_receive(:schedule_downtime).with(@test_machine2, 1200)
    success = 0
    @test.schedule_downtime(@test_machines, 1200) do
      on :success do
        success += 1
      end
    end
    success.should eql 2
  end

  it 'should cancell downtime for all machines and callback success' do
    @mock_service.should_receive(:cancel_downtime).with(@test_machine1)
    @mock_service.should_receive(:cancel_downtime).with(@test_machine2)
    success = 0
    @test.cancel_downtime(@test_machines) do
      on :success do
        success += 1
      end
    end
    success.should eql 2
  end
end

describe Support::Nagios::Service::Http do
  class NagiosServiceHttpTest < WebTestFramework::SimpleTest
    def invoke_test_server_with_fixture_and_create_service(fixture_file)
      setup_test_server_with_fixture(fixture_file)
      Support::Nagios::Service::Http.new(nagios_servers: {
                                           'oy' => 'localhost',
                                           'pg' => 'localhost'
                                         },
                                         nagios_api_port: 5152)
    end

    def fixture_path
      File.join(File.dirname(__FILE__), "fixtures")
    end
  end

  before do
    @test = NagiosServiceHttpTest.new('', 5152)
    @test_machine = Stacks::MachineDef.new("test")
    @env = Stacks::Environment.new("env", { primary_site: "oy" }, nil, {}, {})
    @test_machine.bind_to(@env)
  end

  after do
    @test.destroy if @test
  end

  it 'should return ok when schedule downtime is successful' do
    service = @test.invoke_test_server_with_fixture_and_create_service('downtime_scheduled_ok')
    service.schedule_downtime(@test_machine).should eql('localhost = OK: scheduled')
  end

  it 'should return ok when schedule downtime results in none found' do
    service = @test.invoke_test_server_with_fixture_and_create_service('downtime_scheduled_none_found')
    service.schedule_downtime(@test_machine).should eql('localhost = OK: none found')
  end

  it 'should return failed when schedule downtime returns non 200 response code' do
    service = @test.invoke_test_server_with_fixture_and_create_service('nonexistant_fixture_causes_500')
    service.schedule_downtime(@test_machine).should eql('localhost = Failed: HTTP response code was 500')
  end

  it 'should return ok when cancel downtime is successful' do
    service = @test.invoke_test_server_with_fixture_and_create_service('downtime_cancelled_ok')
    service.cancel_downtime(@test_machine).should eql('localhost = OK: cancelled')
  end

  it 'should return ok when cancel downtime results in a none found' do
    service = @test.invoke_test_server_with_fixture_and_create_service('downtime_cancelled_none_found')
    service.cancel_downtime(@test_machine).should eql('localhost = OK: none found')
  end

  it 'should return no nagios server for fabric' do
    test_machine_in_me = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", { primary_site: "me" }, nil, {}, {})
    test_machine_in_me.bind_to(env)
    service = @test.invoke_test_server_with_fixture_and_create_service('downtime_cancelled_none_found')
    service.cancel_downtime(test_machine_in_me).should eql('skipping env-test - No nagios server found for me')
  end
end
