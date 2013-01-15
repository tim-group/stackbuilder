shared_examples_for "ping" do |machine|
  it "responds to ping on its management network" do

    puts ">>> PINGING TO #{machine.name}"
    output = `/bin/ping -c 1 -nq #{machine.fqdn} 2>&1`
    $?.should eql(0), output
  end
end
