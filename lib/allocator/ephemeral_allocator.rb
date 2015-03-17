require 'allocator/namespace'

class StackBuilder::Allocator::EphemeralAllocator
  def initialize(options)
    @host_repository = options[:host_repository]
  end

  def allocate(specs)
    grouped_specs = specs.group_by { |spec| spec[:fabric] }
    grouped_specs.map do |fabric, fabric_specs|
      hosts = @host_repository.find_compute_nodes(fabric)
      hosts.do_allocation(fabric_specs)
    end.reduce do |result1, result2|
      return {
        :newly_allocated => result1[:newly_allocated].merge(result2[:newly_allocated]),
        :already_allocated => result1[:already_allocated].merge(result2[:already_allocated])
      }
    end
  end
end
