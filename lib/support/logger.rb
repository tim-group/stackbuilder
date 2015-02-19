require 'logger'
require 'support/namespace'

class Support::RakeFormatter
  @@interactive = $stdout.tty? || ENV.key?("BUILD_NUMBER")
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
      msg = msg.gsub(/success/, "\e[32msuccess\e[0m")
      msg = msg.gsub(/successful/, "\e[32msuccessful\e[0m")
      msg = msg.gsub(/failed/, "\e[31mfailed\e[0m")
    end
    msg
  end
end
