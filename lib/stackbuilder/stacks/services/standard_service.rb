module Stacks::Services::StandardService
  attr_accessor :database_username
  alias_method :database_application_name, :database_username
end
