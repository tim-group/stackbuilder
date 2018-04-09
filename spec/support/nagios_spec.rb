require 'stackbuilder/support/nagios'

def new_environment(name, options)
  Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
end

describe Support::Nagios::Service do
  class MockService
    def schedule_downtime(_machine, _duration)
      'OK'
    end

    def cancel_downtime(_machine)
      'OK'
    end
  end

  before do
    @mock_service = MockService.new
    @test = Support::Nagios::Service.new(:service => @mock_service)
    env = new_environment('env', :primary_site => 'oy')
    @test_machine1 = Stacks::MachineDef.new(self, 'test1', env, 'oy')
    @test_machine2 = Stacks::MachineDef.new(self, 'test2', env, 'oy')
    @test_machine1.bind_to(env)
    @test_machine2.bind_to(env)
    @test_machines = [@test_machine1, @test_machine2]
  end

  it 'should schedule downtime for all machines and callback success' do
    expect(@mock_service).to receive(:schedule_downtime).with(@test_machine1, 1200)
    expect(@mock_service).to receive(:schedule_downtime).with(@test_machine2, 1200)
    success = 0
    @test.schedule_downtime(@test_machines, 1200) do
      on :success do
        success += 1
      end
    end
    expect(success).to eql 2
  end

  it 'should cancel downtime for all machines and callback success' do
    expect(@mock_service).to receive(:cancel_downtime).with(@test_machine1)
    expect(@mock_service).to receive(:cancel_downtime).with(@test_machine2)
    success = 0
    @test.cancel_downtime(@test_machines) do
      on :success do
        success += 1
      end
    end
    expect(success).to eql 2
  end
end
