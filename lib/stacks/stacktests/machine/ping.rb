shared_examples_for "ping" do |machine|
  it "responds to ping on its management network" do
    dnsserver = '172.16.16.5'
    ip = `dig #{machine.hostname}.mgmt.#{machine.domain} @#{dnsserver} +short`.chomp

    raise "cant resolve machine #{machine.fqdn}" if ip.nil? or ip==""

    exitcode = -1
    output = ""
    10.times do
      output = `/bin/ping -c 1 -W 1 -n #{ip} 2>&1`
      unless $?.to_i==0
        sleep 4
        next
      end
      exitcode = $?
      break
    end

    exitcode.to_i.should eql(0), output

  end
end
