require 'support/mcollective_puppet'

# probably the wrong way to do this
class Support::MCollectivePuppet_Test
  include Support::MCollectivePuppet
  def initialize(callouts, mco)
    @callouts = callouts
    @mco = mco
  end

  def puppetca(&block)
    @callouts.puppetca()
    block.call(@mco)
  end

  def puppetd(nodes, &block)
    @callouts.puppetd(nodes)
    block.call(@mco)
  end

  def now
    @callouts.now()
  end

end

describe Support::MCollectivePuppet do

  before :each do
    @callouts = double
    @mco = double
    @mcollective_puppet = Support::MCollectivePuppet_Test.new(@callouts, @mco)
    
    @callouts.should_receive(:now).any_number_of_times do
      Time.now
    end
  end

  it 'returns promptly if all machines\' puppet agents are stopped' do
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm2.test.net.local', :data => {:status => 'stopped'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}},
      {:sender => 'vm2.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])
    
    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
  end

  it 'checks again if one machine\'s puppet agent is not stopped' do
    # queries status for all machines
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm2.test.net.local', :data => {:status => 'running'}}
    ])

    # then goes on to get the results from the machine which did stop
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    # then checks the status again for all machines (not just the machine which didn't stop)
    @callouts.should_receive(:puppetd).with(["vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm2.test.net.local', :data => {:status => 'stopped'}}
    ])

    # then gets the results from both machines
    @callouts.should_receive(:puppetd).with(["vm2.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm2.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
  end

  it 'throws an exception if any machines fail' do
    @callouts.should_receive(:puppetd).with(["vm0.test.net.local", "vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm0.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm2.test.net.local', :data => {:status => 'stopped'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm0.test.net.local", "vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm0.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}},
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 1, 'failed_to_restart' => 0}}},
      {:sender => 'vm2.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 1}}}
    ])

    expect {
      @mcollective_puppet.wait_for_complete(["vm0.test.net.local", "vm1.test.net.local", "vm2.test.net.local"])
    }.to raise_error("some machines did not successfully complete puppet runs within 900 sec: vm1.test.net.local (failed), vm2.test.net.local (failed)")
  end

  it 'throws an exception if machines are still running when the time runs out' do
    @callouts.rspec_reset

    @callouts.should_receive(:now).ordered.and_return(0) # start_time

    @callouts.should_receive(:now).ordered.and_return(1) # timed_out
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm2.test.net.local', :data => {:status => 'running'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm1.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @callouts.should_receive(:now).ordered.and_return(1000000) # timed_out

    expect {
      @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
    }.to raise_error("some machines did not successfully complete puppet runs within 900 sec: vm2.test.net.local (running)")
  end

  it 'accounts for machines even if they do not appear at first' do
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm1.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @callouts.should_receive(:puppetd).with(["vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm2.test.net.local', :data => {:status => 'stopped'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm2.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm2.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
  end

  it 'throws an exception if machines are still unaccounted for when the time runs out' do
    @callouts.rspec_reset
    
    @callouts.should_receive(:now).ordered.and_return(0) # start_time

    @callouts.should_receive(:now).ordered.and_return(1) # timed_out
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}}
    ])

    @callouts.should_receive(:puppetd).with(["vm1.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @callouts.should_receive(:now).ordered.and_return(1000000) # timed_out

    expect {
      @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
    }.to raise_error("some machines did not successfully complete puppet runs within 900 sec: vm2.test.net.local (unaccounted for)")
  end

end
