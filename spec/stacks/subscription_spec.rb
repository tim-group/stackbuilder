require 'stacks/subscription'
require 'securerandom'

describe Subscription do

  RSpec::Matchers.define :have_messages_for_hosts do |expected|
    match do |actual|
      actual_hosts = actual.map {|hash| hash["host"]}
      expected == actual_hosts
    end
  end

  def random_topic
    SecureRandom.hex
  end

  it 'waits for all hosts to check-in' do
    topic = random_topic
    subscription = Subscription.new(:pop_timeout=>1)
    subscription.start(topic)

    threads = []
    threads << Thread.new {
      subscription.stomp.publish("/topic/#{topic}", {"host"=>"a"}.to_json)
      subscription.stomp.publish("/topic/#{topic}", {"host"=>"b"}.to_json)
    }

    events = subscription.wait_for_hosts(topic, ["a","b"])
    events.should have_messages_for_hosts(["a","b"])
  end

  it 'returns anyway after the timeout with some results missing' do
    topic = random_topic
    subscription = Subscription.new(:pop_timeout=>1)
    subscription.start(topic)

    threads = []
    threads << Thread.new {
      subscription.stomp.publish("/topic/#{topic}", {"host"=>"a"}.to_json)
    }

    events = subscription.wait_for_hosts(topic, ["a","b"])
    events.should have_messages_for_hosts(["a"])
  end

  it 'can wait for multiple topics' do
    topic = random_topic
    topic2 = random_topic

    subscription2 = Subscription.new(:pop_timeout=>1)
    subscription2.start([topic, topic2])

    threads = []
    threads << Thread.new {
      subscription2.stomp.publish("/topic/#{topic}", {"host"=>"a"}.to_json)
      subscription2.stomp.publish("/topic/#{topic2}", {"host"=>"a"}.to_json)
    }

    subscription2.wait_for_hosts(topic, ["a"]).should have_messages_for_hosts(["a"])
    subscription2.wait_for_hosts(topic2, ["a"]).should have_messages_for_hosts(["a"])
  end
end