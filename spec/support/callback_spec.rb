require 'stacks/factory'

describe Support::Callback do
  it 'allows callbacks to be passed in and executed by the subject code' do
    event_called = false
    callback = Support::Callback.new do
      on :event do |arg|
        arg.blah
        event_called = true
      end
    end
    mock = double
    mock.should_receive(:blah)
    callback.invoke(:event, mock)
    event_called.should eql(true)
  end

  it 'does not raise an error if a callback is not defined for an event' do
    callback = Support::Callback.new
    callback.invoke(:event, mock)
  end

  it 'dispatches summary events when the callback is finished' do
    passed_args = nil
    callback = Support::Callback.new do
      has :event do |args|
        passed_args = args
      end
    end

    callback.invoke(:event, "foo")
    callback.invoke(:event, "bar")
    callback.finish

    passed_args.should eql(%w(foo bar))
  end
end
