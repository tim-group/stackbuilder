metadata :name => 'K8ssecret',
         :description => 'Inserts Kubernetes secrets from data stored within Hiera',
         :author => 'TIM Infrastructure',
         :license => '',
         :url => '',
         :version => 1,
         :timeout => 60

action 'insert', :description => 'Lookup and insert a hiera value into a Kubernetes secret resource' do
end
