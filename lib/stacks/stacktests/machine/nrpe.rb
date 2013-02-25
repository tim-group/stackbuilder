shared_examples_for "nrpe" do |machine|
  commands = mco_client("nrpe",:nodes=>[machine.mgmt_fqdn]) do |mco|
    results = []
    mco.runallcommands().each do |resp|
      results << resp[:data][:commands]
    end
    results
  end

  unless commands.nil? or commands[0].nil?
    pp commands[0]
    commands[0].each do |command,command_result|
      it "#{command}" do
        if (command_result[:exitcode]!=0)
          pp command_result
          fail(command_result[:output])
        end
      end
    end
  end
end
