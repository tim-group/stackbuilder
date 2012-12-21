require 'stacks/mcollective/support'
pp environments

describe 'bah' do
 it "doed " do
    mcollective_fabric do
      pp ping()
    end

    machine.should be_able_to_connect_to(virtualservice)

    ## nrpe
    ## connectivity

    ## end2end from provisioning-host

#   result = mcollective_local.run_puppet()
 #  pp result
 end
end
