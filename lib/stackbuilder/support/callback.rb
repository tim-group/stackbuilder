require 'stackbuilder/support/namespace'

class Support::Callback
  def initialize(&block)
    @blocks = {}
    @summary_blocks = {}
    @summary_args = Hash.new { |h, k| h[k] = [] }
    instance_eval(&block) if block
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
    @summary_args[event] << arg unless @summary_blocks[event].nil?
    @blocks[event].call(arg) unless @blocks[event].nil?
  end

  def finish
    @summary_blocks.each do |event, summary_block|
      args = @summary_args[event]
      summary_block.call(args) unless args.empty?
    end
  end
end
