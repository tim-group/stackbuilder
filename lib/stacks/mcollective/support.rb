module Stacks
  module MCollective
    module Support
       attr_accessor :scope                                                      
                                                                                 
       class MCollectiveRunner                                                   
         def run_puppet                                                          
         end                                                                     
       end                                                                       
                                                                                 
       def mcollective_local(&block)                                             
         return MCollectiveRunner.new                                            
       end                                                                       
                                                                                 
       def mcollective_fabric(&block)                                            
       end                

    end
  end
end
