stack "infra" do
 puppetmaster
 loadbalancer "lb"
end

stack "ref" do
  virtualservice "refapp"
end

env "devx" do
  stack "infra"
  stack "ref"
end
