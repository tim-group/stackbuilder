require 'allocator/namespace'

class StackBuilder::Allocator::EphemeralAllocator

  def initialize(options)
    @host_repository = options[:host_repository]
  end

  def allocate(specs)
    fabrics = specs.map do |spec|
      spec[:fabric]
    end.uniq

    # TODO: nasty: clever way to fold results.
    fabrics.each do |fabric|
      hosts = @host_repository.find_current(fabric)
      return hosts.do_allocation(specs)
    end
  end
end
