require 'stackbuilder/stacks/factory'

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
    expect(mock).to receive(:blah)
    callback.invoke(:event, mock)
    expect(event_called).to eql(true)
  end

  it 'does not raise an error if a callback is not defined for an event' do
    callback = Support::Callback.new
    callback.invoke(:event, double)
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

    expect(passed_args).to eql(%w(foo bar))
  end
end
