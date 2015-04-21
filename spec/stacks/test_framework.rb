require 'set'
require 'stacks/namespace'
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

  def it_stack(desc, &block)
    subject = @subject
    it "stack #{desc}" do
      block.call(subject)
    end
  end
end

module Stacks::Matchers
  RSpec::Matchers.define :have_host do |fqdn|
    match do |stacks|
      stacks.exist?(fqdn)
    end

    failure_message_for_should do
      "Expected to have host: #{fqdn}"
    end

    failure_message_for_should_not do
      "Expected to not have host: #{fqdn}"
    end
  end

  RSpec::Matchers.define :have_hosts do |hosts|
    match do |stacks|
      stacks.fqdn_list - hosts == []
    end

    failure_message_for_should do
      "Expected: #{hosts}\nActual: #{stacks.fqdn_list}\nDiff: #{hosts - stacks.fqdn_list}"
    end

    failure_message_for_should_not do
      "Expected to not have: #{hosts}\nActual: #{stacks.fqdn_list}\nDiff: #{hosts - stacks.fqdn_list}"
    end
  end

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
