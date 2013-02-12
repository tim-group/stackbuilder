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
  log = Logger.new STDOUT
  log.instance_eval do
    @formatter = Support::RakeFormatter.new
    def start(task)
      puts "\e[1m\e[34m:#{task}\e[0m"
    end

    def failed()
      puts "\n\e[1m\e[31mBUILD FAILED\e[0m\n"
    end

    def passed()
    end
  end
  log
end
