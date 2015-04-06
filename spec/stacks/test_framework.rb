require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'
require 'matchers/server_matcher'

module Stacks::TestFramework
  attr_reader :stacks

  def given(&block)
    stacks = Object.new
    stacks.extend Stacks::DSL
    stacks.instance_eval(&block)
    @subject = @stacks = stacks
  end

  def host(host, &block)
    subject = @subject
    it "#{host}" do
      host = subject.find(host)
      block.call(host)
    end
  end

  def model(_desc, &block)
    subject = @subject
    it '#{desc}' do
      block.call(subject)
    end
  end
end

module Stacks::Matchers
  RSpec::Matchers.define :have_ancestory do |expected_ancestory|
    match do |server|
      traversal = stacks.environments[expected_ancestory.shift]

      expected_ancestory.each do |ancestor|
        traversal = traversal[ancestor]
      end

      traversal.should eql(server)
    end

    # failure_message_for_should do |server|
    # end

    # failure_message_for_should_not do |actual|
    # end
  end
end

def describe_stack(name, &block)
  describe name do
    extend Stacks::TestFramework
    extend RSpec::Matchers
    extend Stacks::Matchers
    instance_eval(&block)
  end
end
