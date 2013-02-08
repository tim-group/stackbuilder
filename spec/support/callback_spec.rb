require 'support/callback'

describe Support::Callback do
  it 'allows callbacks to be passed in and executed by the subject code' do
    callback = Support::Callback.new
    event_called = false
    callback.instance_eval do
      on :event do |arg|
        arg.blah()
        event_called = true
      end
    end
    mock = double
    mock.should_receive(:blah)
    callback.invoke(:event, mock)
    event_called.should eql(true)
  end

  it 'raises an error if a callback is not defined for an event' do
    callback = Support::Callback.new
    callback.invoke(:event, mock)
  end

  it 'allows us to invoke a summary event' do
    callback = Support::Callback.new
    summary = false
    callback.instance_eval do
      on :event do |arg|
      end
      on :summary do |arg|
        summary = true
      end
    end
    callback.invoke(:event, "hello")
    callback.invoke(:summary, :if=>[:event])
    summary.should eql(true)
  end

  it 'doesnt invoke a summary invent if the other event is not invoked' do
    callback = Support::Callback.new
    summary = false
    callback.instance_eval do
      on :event do |arg|
      end
      on :summary do |arg|
        summary = true
      end
    end
    callback.invoke(:summary, "hello", :if=>[:event])
    summary.should eql(false)
  end


end


