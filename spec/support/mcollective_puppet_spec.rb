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
      {:sender => 'vm2.test.net.local', :data => {:status => 'not yet stopped, but cannot remember what the code for that is'}}
    ])

    # then goes on to get the results from the machine which did stop
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    # then checks the status again for all machines (not just the machine which didn't stop)
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:status).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:status => 'stopped'}},
      {:sender => 'vm2.test.net.local', :data => {:status => 'stopped'}}
    ])

    # then gets the results from both machines
    @callouts.should_receive(:puppetd).with(["vm1.test.net.local", "vm2.test.net.local"]).ordered
    @mco.should_receive(:last_run_summary).ordered.and_return([
      {:sender => 'vm1.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}},
      {:sender => 'vm2.test.net.local', :data => {:resources => {'failed' => 0, 'failed_to_restart' => 0}}}
    ])

    @mcollective_puppet.wait_for_complete(["vm1.test.net.local", "vm2.test.net.local"])
  end

end
