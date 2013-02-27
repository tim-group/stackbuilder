require 'puppet'
require 'puppet/indirector/node/stacks'

describe Puppet::Node::Stacks do

  it 'loads enc data correctly' do

    class Puppet::Node
      def fact_merge
        parameters[:fqdn]='srs-refapp-001.mgmt.st.net.local'
      end
    end

#    enc = Puppet::Node::Stacks.new
 #   request = Puppet::Indirector::Request.new('xxx','xxx','xxx','srs-refapp-001')
  #  pp enc.find(request)
  end

end
