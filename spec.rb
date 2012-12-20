require 'stacks/mcollective/support'
pp environments

describe 'bah' do
 it "doed " do
    mcollective_local do
        print "hello world"
    end

#   result = mcollective_local.run_puppet()
 #  pp result
 end
end
