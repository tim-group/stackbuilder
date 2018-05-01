require 'stackbuilder/support/mcollective'

include ::Support::MCollective

shared_examples_for "nrpe" do |machine|
  commands = mco_client("nrpe", :nodes => [machine.mgmt_fqdn]) do |mco|
    results = []
    mco.runallcommands.each do |resp|
      results << resp[:data][:commands]
    end
    results
  end

  if commands.empty?
    fail("no nrpe checks executed on host #{machine.mgmt_fqdn}")
  end

  unless commands.nil? || commands[0].nil?
    commands[0].each do |command, command_result|
      it "#{command}" do
        fail(command_result[:output]) if command_result[:exitcode] != 0
      end
    end
  end
end
