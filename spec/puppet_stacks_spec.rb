require 'puppet'
require 'puppet/indirector/node/stacks'

describe Puppet::Node::Stacks do

  it 'loads enc data correctly' do
    enc = Puppet::Node::Stacks.new
    request = Puppet::Indirector::Request.new('xxx','xxx','srs-refapp-001')
    pp enc.find(request)
  end

end
