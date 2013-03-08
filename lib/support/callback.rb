module Support
end

class Support::Callback
  def initialize(&block)
    @blocks = {}
    @summary_blocks = {}
    @invoked = Hash.new { |h, k| h[k] = [] }
    if block:
      instance_eval(&block)
    end
  end

  private

  def on(event, &block)
    @blocks[event] = block
  end

  def has(event, &block)
    @summary_blocks[event] = block
  end

  public

  def invoke(event, arg, options={})
    @invoked[event] << arg

    unless @blocks[event].nil?
      if options.has_key? :if
        options[:if].each do |key|
          return unless @invoked.has_key? key
        end
      end
      @blocks[event].call(arg)
    end
  end

  def finish
    @invoked.keys.each do |event|
      summary_block = @summary_blocks[event]
      if not summary_block.nil?
        summary_block.call(@invoked[event])
      end
    end
  end

end
