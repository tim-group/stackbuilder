require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/subscription'

describe Subscription do
  RSpec::Matchers.define :have_messages_for_hosts do |expected|
    match do |actual|
      actual_hosts = actual.map { |hash| hash["host"] }
      expected == actual_hosts
    end
  end

  def random_topic
    SecureRandom.hex
  end

  # FIXME: rpearce 28/04/2016 this continues to flicker, go away.
  xit 'waits for all hosts to check-in' do
    topic = random_topic
    subscription = Subscription.new(:pop_timeout => 1, :minimum_wait => 0)
    subscription.start([topic])

    threads = []
    threads << Thread.new do
      subscription.stomp.publish("/topic/#{topic}", { "host" => "a" }.to_json)
      subscription.stomp.publish("/topic/#{topic}", { "host" => "b" }.to_json)
    end

    events = subscription.wait_for_hosts(topic, %w(a b))
    expect(events.responses).to have_messages_for_hosts(%w(a b)) # XXX flicker
  end

  it 'returns anyway after the timeout with some results missing' do
    topic = random_topic
    subscription = Subscription.new(:pop_timeout => 1, :minimum_wait => 0)
    subscription.start([topic])

    threads = []
    threads << Thread.new do
      subscription.stomp.publish("/topic/#{topic}", { "host" => "a" }.to_json)
    end

    # 08.05.2015 mmazurek: 0.01 might be to slow, bump if causing specs to fail, remove comment if fine after a while
    events = subscription.wait_for_hosts(topic, %w(a b), 0.01)
    expect(events.responses).to have_messages_for_hosts(["a"])
  end

  xit 'can wait for multiple topics' do
    topic = random_topic
    topic2 = random_topic

    subscription2 = Subscription.new(:pop_timeout => 1, :minimum_wait => 0)
    subscription2.start([topic, topic2]) # XXX flicker

    threads = []
    threads << Thread.new do
      subscription2.stomp.publish("/topic/#{topic}", { "host" => "a" }.to_json)
      subscription2.stomp.publish("/topic/#{topic2}", { "host" => "a" }.to_json)
    end

    expect(subscription2.wait_for_hosts(topic, ["a"]).responses).to have_messages_for_hosts(["a"]) # XXX flicker
    expect(subscription2.wait_for_hosts(topic2, ["a"]).responses).to have_messages_for_hosts(["a"])
  end

  xit 'correctly shows: successful, failed and unknowns' do
    topic = random_topic

    subscription = Subscription.new(:pop_timeout => 0.05, :minimum_wait => 0)
    subscription.start([topic]) # XXX flicker

    threads = []
    threads << Thread.new do
      subscription.stomp.publish("/topic/#{topic}", { "host" => "a", "status" => "changed" }.to_json)
      subscription.stomp.publish("/topic/#{topic}", { "host" => "b", "status" => "failed" }.to_json)
    end

    # 08.05.2015 mmazurek: 0.1 might be to slow, bump if causing specs to fail, remove comment if fine after a while
    result = subscription.wait_for_hosts(topic, %w(a b c), 0.1)

    expect(result.passed).to eql(["a"]) # XXX flicker
    expect(result.failed).to eql(["b"])
    expect(result.unaccounted_for).to eql(["c"])

    expect(result.all).to eql("a" => "success",
                              "b" =>  "failed",
                              "c" =>  "unaccounted_for")
    expect(result.all_passed?).to eql(false)
  end
end
