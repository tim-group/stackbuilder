require 'logger'
module Support
end

class Support::RakeFormatter
  Format = "\t\e[1m[%s]\e[0m %s\n"
  attr_accessor :datetime_format
  def call(severity, time, progname, msg)
    Format % [severity.clone.downcase!, msg2str(msg)]
  end

  def msg2str(msg)
    msg = msg.gsub(/successful/, "\e[32msuccessful\e[0m")
    msg = msg.gsub(/failed/, "\e[31mfailed\e[0m")
  end
end

def logger
  return @log unless @log.nil?

  @log = Logger.new STDOUT
  @log.instance_eval do
    @formatter = Support::RakeFormatter.new
    def start(task)
      @start_time = Time.now
      puts "\e[1m\e[34m:#{task}\e[0m"
    end

    def failed(task)
      @elapsed = Time.now - @start_time
      puts "\n\e[1m\e[31m:#{task} failed in #{@elapsed}\e[0m\n"
    end

    def passed(task)
      @elapsed = Time.now - @start_time
      puts "\n\e[1m\e[32m:#{task} passed in #{@elapsed}s\e[0m\n"
    end
  end
  @log
end
