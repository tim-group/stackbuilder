module Support
end

class Support::Callback
  def initialize(&block)
    @blocks = {}
    @summary_blocks = {}
    @summary_args = Hash.new { |h, k| h[k] = [] }
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

  def invoke(event, arg)
    unless @summary_blocks[event].nil?
      @summary_args[event] << arg
    end

    unless @blocks[event].nil?
      @blocks[event].call(arg)
    end
  end

  def finish
    @summary_blocks.each do |event, summary_block|
      args = @summary_args[event]
      unless args.empty?
        summary_block.call(args)
      end
    end
  end

end
