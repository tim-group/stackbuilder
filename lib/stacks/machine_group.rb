# FIXME: This appears to provide a mechanism for late binding through composition.
# However many of the methods/variables that were previously used here actually came from machine_set.
# This was potentially very confusing as it was not clear where variables we coming from.
# To reduce this complexity we have therefore moved all methods and functionality to machine_set
# Below is the only method that remains to ensure the late binding behaviour.
module Stacks::MachineGroup
  def self.extended(object)
    object.configure
  end
end
