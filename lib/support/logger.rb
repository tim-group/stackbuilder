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
      msg = msg.gsub(/(success\w*)/, "\e[32m\\1\e[0m")
      msg = msg.gsub(/(fail\w*)/, "\e[31m\\1\e[0m")
    end
    msg
  end
end
