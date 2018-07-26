require 'stackbuilder/support/namespace'

module Support::Forking
  class Future
    def initialize(&block)
      @block = block
    end

    def value
      @block.call
    end
  end

  def async_fork_and_return(&block)
    read, write = IO.pipe
    pid = fork do
      begin
        read.close
        result = nil
        exception = nil
        result = block.call
      rescue StandardError => e
        exception = "#{e.message}\n  #{e.backtrace.join("\n  ")}"
      end
      Marshal.dump({ :result => result, :exception => exception }, write)
      exit 0
    end

    write.close

    Future.new do
      serialized_result = read.read
      _, status = Process.waitpid2(pid)
      fail "non-zero return from child process #{status.inspect}" unless status.success?

      result = Marshal.load(serialized_result)
      fail "child process raised exception: #{result[:exception]}" unless result[:exception].nil?
      result[:result]
    end
  end
end
