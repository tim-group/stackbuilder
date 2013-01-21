shared_examples_for "ping" do |machine|
  it "responds to ping on its management network" do
    interval = 0.25 # seconds; can't go <0.2 unless root
    deadline = 10 # seconds; with this set, count is the count of successful responses required, not requests to send
    required_count = 3 # seconds
    output = `/bin/ping -i #{interval} -w #{deadline} -c #{required_count} -n #{machine.mgmt_fqdn} 2>&1`
    $?.exitstatus.should eql(0), "exitstatus = #{$?.exitstatus}\n#{output}"
  end
end
