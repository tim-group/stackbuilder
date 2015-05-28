require 'stackbuilder/stacks/factory'

describe Support::Forking do
  include Support::Forking

  it 'returns multiple futures for async execs' do
    future1 = async_fork_and_return do
      1
    end

    future2 = async_fork_and_return do
      2
    end

    future1.value.should eql(1)
    future2.value.should eql(2)
  end

  it 'throws an exception if a mistake was made' do
    expect do
      async_fork_and_return.value do
        provisio # syntax error
      end.value
    end.to raise_error
  end
end
