module Support
end

class Support::Callback
  def initialize
    @blocks = {}
  end

  private
  def on(event, &block)
    @blocks[event] = block
  end

  public
  def invoke(event, arg)
    unless @blocks[event].nil?
      @blocks[event].call(arg)
    end
  end
end
