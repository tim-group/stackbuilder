require 'logger'
module Support
end

class Support::RakeFormatter
  @@interactive = $stdout.tty? || ENV.has_key?("BUILD_NUMBER")
  @@format = @@interactive ? "\t\e[1m[%s]\e[0m %s\n" : "\t[%s] %s\n"
  attr_accessor :datetime_format

  def interactive?
    @@interactive
  end

  def call(severity, time, progname, msg)
    @@format % [severity.clone.downcase!, msg2str(msg)]
  end

  def msg2str(msg)
    if @@interactive
      msg = msg.gsub(/successful/, "\e[32msuccessful\e[0m")
      msg = msg.gsub(/failed/, "\e[31mfailed\e[0m")
    end
    msg
  end
end

def logger
  return @log unless @log.nil?

  @log = Logger.new STDOUT
  @log.instance_eval do
    @formatter = Support::RakeFormatter.new
    def start(task)
      @start_time = Time.now
      if @formatter.interactive?
        puts "\e[1m\e[34m:#{task}\e[0m"
      else
        puts ":#{task}"
      end
    end

    def failed(task)
      @elapsed = Time.now - @start_time
      if @formatter.interactive?
        puts "\n\e[1m\e[31m:#{task} failed in #{@elapsed}\e[0m\n"
      else
        puts "\n:#{task} failed in #{@elapsed}\n"
      end
    end

    def passed(task)
      @elapsed = Time.now - @start_time
      if @formatter.interactive?
        puts "\n\e[1m\e[32m:#{task} passed in #{@elapsed}s\e[0m\n"
      else
         puts "\n:#{task} passed in #{@elapsed}s\n"
      end
    end
  end
  @log
end

