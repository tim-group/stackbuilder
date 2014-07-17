require 'web-test-framework'
require 'support/nagios'

describe Support::Nagios::HttpHelper do
  class NagiosHelperTest  < WebTestFramework::SimpleTest

    def invoke_test_server_with_fixture_and_create_helper(fixture_file, port='5152')
        setup_test_server_with_fixture(fixture_file)
        options = {
          :nagios_servers  => ['localhost:5152'],
        }
        Support::Nagios::Helper.new(options)
    end

    def fixture_path
        File.join(File.dirname(__FILE__), "fixtures")
    end
  end

  before do
    @test = NagiosHelperTest.new('', 5152)
  end

  after do
    @test.destroy if @test
  end

  it 'should return ok when schedule downtime is successful' do
    helper = @test.invoke_test_server_with_fixture_and_create_helper('downtime_scheduled_ok')
    helper.schedule_downtime('localhost').should eql({
      'localhost:5152' => "OK: scheduled"
    })
  end

  it 'should return ok when schedule downtime results in none found' do
    helper = @test.invoke_test_server_with_fixture_and_create_helper('downtime_scheduled_none_found')
    helper.schedule_downtime('localhost').should eql({
      'localhost:5152' => "OK: none found"
    })
  end

  it 'should return failed when schedule downtime returns non 200 response code' do
    helper = @test.invoke_test_server_with_fixture_and_create_helper('nonexistant_fixture_causes_500')
    helper.schedule_downtime('localhost').should eql({
      'localhost:5152' => "Failed: HTTP response code was 500"
    })
  end


  it 'should return ok when cancel downtime is successful' do
    helper = @test.invoke_test_server_with_fixture_and_create_helper('downtime_cancelled_ok')
    helper.cancel_downtime('localhost').should eql({
      'localhost:5152' => "OK: cancelled"
    })
  end

  it 'should return ok when cancel downtime results in a none found' do
    helper = @test.invoke_test_server_with_fixture_and_create_helper('downtime_cancelled_none_found')
    helper.cancel_downtime('localhost').should eql({
      'localhost:5152' => "OK: none found"
    })
  end

end
