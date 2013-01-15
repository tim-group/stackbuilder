shared_examples_for "ping" do |machine|
  it "responds to ping on its management network" do
    output = `/bin/ping -c 1 -W 1 -n #{machine.fqdn} 2>&1`
    $?.should eql(0), output
  end
end
