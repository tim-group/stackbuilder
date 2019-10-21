require 'stackbuilder/support/digest_generator'

describe Support::DigestGenerator do
  it "produces different digests for two hashes that have the same content in a different order" do
    hash1 = { "podSelector" => { "matchLabels" => { "machineset" => "myapp", "group" => "blue", "app.kubernetes.io/component" => "app_service" } },
              "policyTypes" => ["Egress"],
              "egress" => [{ "to" => [{ "ipBlock" => { "cidr" => "3.1.4.2/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.5/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.4/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.6/32" } }],
                             "ports" => [{ "protocol" => "TCP", "port" => 3306 }] }] }

    hash2 = { "podSelector" => { "matchLabels" => { "machineset" => "myapp", "group" => "blue", "app.kubernetes.io/component" => "app_service" } },
              "policyTypes" => ["Egress"],
              "egress" => [{ "to" => [{ "ipBlock" => { "cidr" => "3.1.4.2/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.6/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.4/32" } },
                                      { "ipBlock" => { "cidr" => "3.1.4.5/32" } }],
                             "ports" => [{ "protocol" => "TCP", "port" => 3306 }] }] }

    digest1 = Support::DigestGenerator.from_hash(hash1)

    digest2 = Support::DigestGenerator.from_hash(hash2)

    expect(digest1).not_to eq digest2
  end
end
