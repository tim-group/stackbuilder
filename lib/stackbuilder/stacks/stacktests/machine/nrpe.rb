require 'stackbuilder/support/mcollective_nrpe'

shared_examples_for "nrpe" do |machine|
  mco_nrpe = Support::MCollectiveNrpe.new
  nrpe_results = mco_nrpe.run_all_commands(machine.mgmt_fqdn)
  nrpe_results.each do |command, command_result|
    it "#{command}" do
      fail(command_result[:output]) if command_result[:exitcode] != 0
    end
  end
end
