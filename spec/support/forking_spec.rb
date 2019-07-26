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

    expect(future1.value).to eql(1)
    expect(future2.value).to eql(2)
  end

  it 'throws an exception if a mistake was made' do
    expect do
      async_fork_and_return do
        provisio
      end.value
    end.to raise_error(/undefined local variable or method `provisio'/)
  end
end
