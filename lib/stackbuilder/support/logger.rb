require 'logger'

module Kernel
  def logger(level = Logger::INFO, &msg)
    return if defined? $options && $options[:verbose] == 0

    logger_initialize unless @console_logger

    @console_logger.add(level, &msg)
  end

  private

  def logger_initialize
    # $options is not defined if the entry path to the codebase is not the 'stacks' executable
    verbosity = defined? $options ? $options[:verbose] : 3

    # TODO: dump debug info to a file as well
    @console_logger = Logger.new STDOUT
    @console_logger.level = case verbosity
                            when 1 then Logger::WARN
                            when 2 then Logger::INFO
                            else Logger::DEBUG
                            end
    @console_logger.formatter = proc do |severity, datetime, _progname, msg|
      fdatetime = datetime.strftime("%Y-%m-%d %H:%M:%S.") << sprintf("%06d", datetime.usec)

      col = case severity
            when 'UNKNOWN' then '[0m'
            when 'FATAL'   then '[31;1m'
            when 'ERROR'   then '[31m'
            when 'WARN'    then '[33m'
            when 'INFO'    then '[34;1m'
            when 'DEBUG'   then '[0m'
            else                '[0m'
      end

      sprintf("#{col}%s (%5d): %s %s[0m\n", fdatetime, $PROCESS_ID, severity, msg2str(msg))
    end
  end

  def msg2str(msg)
    case msg
    when ::String
      msg
    when ::Exception
      "#{msg.message} (#{msg.class})\n" << (msg.backtrace || []).join("\n")
    else
      msg.inspect
    end
  end
end
