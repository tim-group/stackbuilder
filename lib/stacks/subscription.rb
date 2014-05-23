require 'mcollective'

class Subscription

  @@loaded = false

  attr_reader :stomp

  def initialize(options = {})
    @queues = {}
    @pop_timeout = options[:pop_timeout] || 30
  end

  def self.create_client()
    configfile = MCollective::Util.config_file_for_user

    if (not @@loaded)
      MCollective::Config.instance.loadconfig(configfile)
      @@loaded = true
    end
    config = MCollective::Config.instance

    Stomp::Client.new(config.pluginconf['rabbitmq.pool.1.user'],
                      config.pluginconf['rabbitmq.pool.1.password'],
                      config.pluginconf['rabbitmq.pool.1.host'],
                      config.pluginconf['rabbitmq.pool.1.port'])
  end


  def self.create_stomp()
    configfile = MCollective::Util.config_file_for_user

    if (not @@loaded)
      MCollective::Config.instance.loadconfig(configfile)
      @@loaded = true
    end
    config = MCollective::Config.instance

    Stomp::Connection.new(config.pluginconf['rabbitmq.pool.1.user'],
                          config.pluginconf['rabbitmq.pool.1.password'],
                          config.pluginconf['rabbitmq.pool.1.host'],
                          config.pluginconf['rabbitmq.pool.1.port'])
  end


  def start(topics)
    @stomp = Subscription.create_client()

    topics.each do |topic|
      @queues[topic] = Queue.new

      @stomp.subscribe("/topic/#{topic}") do |msg|
        @queues[topic] << msg
      end
    end
  end

  def wait_for_hosts(topic, hosts, timeout = 1)
    start_time = Time.now

    return_results = []
    message = nil

    while(not is_all_accounted_for(return_results, hosts) and not timed_out(start_time, timeout))
      begin
        Timeout::timeout(@pop_timeout) do
          message = @queues[topic].pop()
        end
        parsed_message = JSON.parse(message.body)
        if hosts.include?(parsed_message["host"])
          return_results << parsed_message
        end
      rescue Timeout::Error => e
        puts e
      end
    end
    return return_results
  end

  private
  def is_all_accounted_for(results, hosts)
    accounted_for = results.map {|hash| hash["host"]}
    (hosts-accounted_for).empty?
  end

  def timed_out(start_time, timeout)
    now = Time.now
    return (now - start_time) > timeout
  end

end