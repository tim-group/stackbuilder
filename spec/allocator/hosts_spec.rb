require 'stackbuilder/allocator/hosts'
require 'stackbuilder/stacks/factory'

describe StackBuilder::Allocator::Hosts do
  before do
    extend Stacks::DSL
  end

  describe 'establish_availability_group_rack_distribution' do
    it 'provides a hash of racks with correct availability group counts' do
      h1 = StackBuilder::Allocator::Host.new("h1", :facts => { 'rack' => 'A' })
      h2 = StackBuilder::Allocator::Host.new("h2", :facts => { 'rack' => 'B' })
      h3 = StackBuilder::Allocator::Host.new("h3", :facts => { 'rack' => 'A' })
      h4 = StackBuilder::Allocator::Host.new("h3", :facts => { 'rack' => 'C' })

      h1.allocated_machines << { :hostname => "refapp1", :availability_group => "refapp" }
      h2.allocated_machines << { :hostname => "refapp2", :availability_group => "refapp" }
      h3.allocated_machines << { :hostname => "refapp3", :availability_group => "refapp" }

      hosts = StackBuilder::Allocator::Hosts.new(:hosts => [h1, h2, h3, h4], :preference_functions => [])
      distribution_hash = hosts.availability_group_rack_distribution
      expect(distribution_hash.key?('A')).to eql(true)
      expect(distribution_hash.key?('B')).to eql(true)
      expect(distribution_hash.key?('C')).to eql(true)

      expect(distribution_hash['A'].key?('refapp')).to eql(true)
      expect(distribution_hash['B'].key?('refapp')).to eql(true)
      expect(distribution_hash['C'].key?('refapp')).to eql(false)

      expect(distribution_hash['A']['refapp']).to eql(2)
      expect(distribution_hash['B']['refapp']).to eql(1)
    end
  end
end
