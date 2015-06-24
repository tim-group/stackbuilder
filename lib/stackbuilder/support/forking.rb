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
        result = nil
        exception = nil
        result = block.call
      rescue StandardError => e
        exception = e
      end
      Marshal.dump({ result: result, exception: exception }, write)
    end
    write.close

    Future.new do
      serialized_result = read.read
      Process.waitpid(pid)
      result = Marshal.load(serialized_result)
      fail result[:exception] unless result[:exception].nil?
      result[:result]
    end
  end
end
