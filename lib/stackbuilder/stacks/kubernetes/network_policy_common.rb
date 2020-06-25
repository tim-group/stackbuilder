module Stacks::Kubernetes::NetworkPolicyCommon
  def create_egress_network_policy(name, env_name, labels, egresses, pod_selector_match_labels)
    spec = {
      'podSelector' => {
        'matchLabels' => pod_selector_match_labels
      },
      'policyTypes' => [
        'Egress'
      ],
      'egress' => egresses
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-out-to-#{name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end
end
