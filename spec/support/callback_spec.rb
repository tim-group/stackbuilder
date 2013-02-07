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
end


