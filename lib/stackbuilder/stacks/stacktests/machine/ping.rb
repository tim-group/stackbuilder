shared_examples_for "ping" do |machine|
  it "responds to ping on its management network" do
    require 'net/ping'

    (1..3).each do
      sleep 0.5
      check = Net::Ping::External.new(machine.mgmt_fqdn)
      check.ping?
      expect(check.ping?).to eql(true)
    end
  end
end
