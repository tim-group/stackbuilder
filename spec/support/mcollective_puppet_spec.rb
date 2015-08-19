require 'stackbuilder/stacks/factory'

# XXX probably the wrong way to do this
class Support::MCollectivePuppetTest
  include Support::MCollectivePuppet
  def initialize(callouts, mco)
    @callouts = callouts
    @mco = mco
  end

  def puppetca(&block)
    @callouts.puppetca
    block.call(@mco)
  end

  def puppetd(nodes, &block)
    @callouts.puppetd(nodes)
    block.call(@mco)
  end

  def now
    @callouts.now
  end
end

describe Support::MCollectivePuppet do
  before :each do
    @callouts = double
    @mco = double
    @mcollective_puppet = Support::MCollectivePuppetTest.new(@callouts, @mco)
    @callback = double

    expect(@callouts).to receive(:now) { 0 }.at_least(1)
  end

  def wait_for_complete_callback
    callback = @callback
    Proc.new do
      on :passed do |vm|
        callback.passed(vm)
      end
      on :failed do |vm|
        callback.failed(vm)
      end
      on :timed_out do |vm, result|
        callback.timed_out(vm, result)
      end
    end
  end

  it 'returns promptly if all machines\' puppet agents are successfully stopped' do
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm2.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end

  it 'checks again if one machine\'s puppet agent is not stopped' do
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'running' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered

    expect(@callouts).to receive(:puppetd).with(["vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm2.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm2.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end

  it 'does not query results if no machines are stopped' do
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'running' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'running' } }
    ])

    # note that there is no call to last_run_summary here!

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm2.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end

  it 'reports failure if any machines fail' do
    expect(@callouts).to receive(:puppetd).with(["vm0.test.net.local", "vm1.test.net.local",
                                                 "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm0.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm0.test.net.local", "vm1.test.net.local",
                                                 "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm0.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 1, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 1 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm0.test.net.local').ordered
    expect(@callback).to receive(:failed).with('vm1.test.net.local').ordered
    expect(@callback).to receive(:failed).with('vm2.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm0.test.net.local", "vm1.test.net.local", "vm2.test.net.local"],
                                          &wait_for_complete_callback)
  end

  it 'considers a machine to be still running if it is stopped but returns a hollow last run summary' do
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local", "vm3.test.net.local",
                                                 "vm4.test.net.local", "vm5.test.net.local", "vm6.test.net.local",
                                                 "vm7.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm3.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm4.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm5.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm6.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm7.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local", "vm3.test.net.local",
                                                 "vm4.test.net.local", "vm5.test.net.local", "vm6.test.net.local",
                                                 "vm7.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => nil },
      { :sender => 'vm2.test.net.local', :data => {} },
      {
        :sender => 'vm3.test.net.local',
        :data => { :summary => { 'resources' => nil } }
      }, # this is the only one which actually occurs, but there's no kill like overkill
      {
        :sender => 'vm4.test.net.local',
        :data => { :summary => { 'resources' => {} } }
      },
      {
        :sender => 'vm5.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => nil, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm6.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => nil } } }
      },
      {
        :sender => 'vm7.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm7.test.net.local').ordered

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local", "vm3.test.net.local",
                                                 "vm4.test.net.local", "vm5.test.net.local", "vm6.test.net.local"
                                                ]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      { :sender => 'vm1.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm2.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm3.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm4.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm5.test.net.local', :data => { :status => 'stopped' } },
      { :sender => 'vm6.test.net.local', :data => { :status => 'stopped' } }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local", "vm3.test.net.local",
                                                 "vm4.test.net.local", "vm5.test.net.local", "vm6.test.net.local"
                                                ]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm3.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm4.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm5.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      },
      {
        :sender => 'vm6.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm2.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm3.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm4.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm5.test.net.local').ordered
    expect(@callback).to receive(:passed).with('vm6.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local", "vm3.test.net.local",
                                           "vm4.test.net.local", "vm5.test.net.local", "vm6.test.net.local",
                                           "vm7.test.net.local"], &wait_for_complete_callback)
  end

  it 'reports an error if machines are still running when the time runs out' do
    RSpec::Mocks.space.proxy_for(@callouts).reset

    expect(@callouts).to receive(:now).ordered.and_return(0) # start_time

    expect(@callouts).to receive(:now).ordered.and_return(1) # timed_out
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :status => 'stopped' }
      },
      {
        :sender => 'vm2.test.net.local',
        :data => { :status => 'running' }
      }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered

    expect(@callouts).to receive(:now).ordered.and_return(1_000_000) # timed_out

    expect(@callback).to receive(:timed_out).with('vm2.test.net.local', 'running').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end

  it 'accounts for machines even if they do not appear at first' do
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :status => 'stopped' }
      }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered

    expect(@callouts).to receive(:puppetd).with(["vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      {
        :sender => 'vm2.test.net.local',
        :data => { :status => 'stopped' }
      }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm2.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm2.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm2.test.net.local').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end

  it 'reports an error if machines are still unaccounted for when the time runs out' do
    RSpec::Mocks.space.proxy_for(@callouts).reset

    expect(@callouts).to receive(:now).ordered.and_return(0) # start_time

    expect(@callouts).to receive(:now).ordered.and_return(1) # timed_out
    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    expect(@mco).to receive(:status).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :status => 'stopped' }
      }
    ])

    expect(@callouts).to receive(:puppetd).with(["vm1.test.net.local"]).ordered
    expect(@mco).to receive(:last_run_summary).ordered.and_return([
      {
        :sender => 'vm1.test.net.local',
        :data => { :summary => { 'resources' => { 'failed' => 0, 'failed_to_restart' => 0 } } }
      }
    ])

    expect(@callback).to receive(:passed).with('vm1.test.net.local').ordered

    expect(@callouts).to receive(:now).ordered.and_return(1_000_000) # timed_out

    expect(@callback).to receive(:timed_out).with('vm2.test.net.local', 'unaccounted for').ordered

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"], &wait_for_complete_callback)
  end
end
