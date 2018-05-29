require 'stackbuilder/allocator/namespace'

class StackBuilder::Allocator::EphemeralAllocator
  def initialize(options)
    @host_repository = options[:host_repository]
  end

  def allocate(specs, excluded_hosts = [], best_effort = false)
    grouped_specs = specs.group_by { |spec| spec[:fabric] }
    grouped_specs.map do |fabric, fabric_specs|
      hosts = @host_repository.find_compute_nodes(fabric).without(excluded_hosts)
      hosts.do_allocation(fabric_specs, best_effort)
    end.reduce do |result1, result2|
      return {
        :newly_allocated => result1[:newly_allocated].merge(result2[:newly_allocated]),
        :already_allocated => result1[:already_allocated].merge(result2[:already_allocated]),
        :failed_to_allocate => result1[:failed_to_allocate].merge(result2[:failed_to_allocate])
      }
    end
  end
end
