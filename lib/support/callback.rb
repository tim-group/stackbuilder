module Support
end

class Support::Callback
  def initialize
    @blocks = {}
    @invoked = {}
  end

  private
  def on(event, &block)
    @blocks[event] = block
  end

  public
  def invoke(event, arg, options={})
    @invoked[event] = true
    unless @blocks[event].nil?

      if options.has_key? :if
        options[:if].each do |key|
          return unless @invoked.has_key? key
        end
      end
      @blocks[event].call(arg)
    end
  end

end
