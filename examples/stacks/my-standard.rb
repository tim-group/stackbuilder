stack 'my_standard' do
  # Create a machineset with app_service capabilities
  standalone_app_service 'standardsrv' do
    self.instances = { 'local' => 1 }
    each_machine do |machine|
      # Specify memory requirements in KB (default: 2097152)
      machine.ram = '2097152'
      # Specify number of virtual cpu cores
      machine.vcpus = '1'
      # Specify disk space for / partition (default: 3G)
      machine.modify_storage({ '/' => { :size => '5G' } })
      # Specify that this machine should use the trusty gold image
      machine.use_trusty
    end
  end
end

