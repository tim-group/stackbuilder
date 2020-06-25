require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1'
                         )
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'stacks/application_credentials_selector' => 0
    )
  end

  def k8s_resource(set, kind)
    set.to_k8s(app_deployer, dns_resolver, hiera_provider).flat_map(&:resources).find { |s| s['kind'] == kind }
  end

  describe 'base service' do
    it 'creates a correct Deployment when the to_k8s method is called' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => { 'e1' => true } do
            self.application = 'test'
            self.startup_alert_threshold = '10s'
            self.alerts_channel = 'test'
            self.maintainers = [person('Testers')]
            self.description = 'Test Description'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expected_deployment = {
        'apiVersion' => 'apps/v1',
        'kind' => 'Deployment',
        "metadata" => {
          "name" => "x-blue-app",
          "namespace" => "e1",
          "labels" => {
            "app.kubernetes.io/managed-by" => "stacks",
            "stack" => "mystack",
            "machineset" => "x",
            "group" => "blue",
            "app.kubernetes.io/instance" => "blue",
            "app.kubernetes.io/part-of" => "x",
            "app.kubernetes.io/component" => "app_service",
            "application" => "test",
            "app.kubernetes.io/name" => "test",
            "app.kubernetes.io/version" => "1.2.3"
          },
          "annotations" => {
            "configmap.reloader.stakater.com/reload" => "x-blue-app",
            "secret.reloader.stakater.com/reload" => "x-blue-app",
            "maintainers" => "[{\"type\":\"Individual\",\"name\":\"Testers\"}]",
            "description" => "Test Description"
          }
        },
        'spec' => {
          "selector" => {
            "matchLabels" => {
              "machineset" => "x",
              "group" => "blue",
              "app.kubernetes.io/component" => "app_service",
              "participation" => "enabled"
            }
          },
          "strategy" => {
            "type" => "RollingUpdate",
            "rollingUpdate" => {
              "maxUnavailable" => 1,
              "maxSurge" => 0
            }
          },
          "progressDeadlineSeconds" => 10,
          "replicas" => 2,
          "template" => {
            "metadata" => {
              "labels" => {
                "participation" => "enabled",
                "app.kubernetes.io/managed-by" => "stacks",
                "stack" => "mystack",
                "machineset" => "x",
                "group" => "blue",
                "app.kubernetes.io/instance" => "blue",
                "app.kubernetes.io/part-of" => "x",
                "app.kubernetes.io/component" => "app_service",
                "application" => "test",
                "app.kubernetes.io/name" => "test",
                "app.kubernetes.io/version" => "1.2.3"
              },
              "annotations" => {
                "seccomp.security.alpha.kubernetes.io/pod" => "runtime/default",
                "maintainers" => "[{\"type\":\"Individual\",\"name\":\"Testers\"}]",
                "description" => "Test Description"
              }
            },
            "spec" => {
              "affinity" => {
                "podAntiAffinity" => {
                  "preferredDuringSchedulingIgnoredDuringExecution" => [{
                    "podAffinityTerm" => {
                      "labelSelector" => {
                        "matchLabels" => {
                          "machineset" => "x",
                          "group" => "blue",
                          "app.kubernetes.io/component" => "app_service"
                        }
                      },
                      "topologyKey" => "kubernetes.io/hostname"
                    },
                    "weight" => 100
                  }]
                }
              },
              "automountServiceAccountToken" => false,
              "containers" => [{
                "securityContext" => {
                  "readOnlyRootFilesystem" => true,
                  "allowPrivilegeEscalation" => false,
                  "capabilities" => {
                    "drop" => ["ALL"]
                  }
                },
                "image" => "repo.net.local:8080/timgroup/test:1.2.3",
                "name" => "test",
                "resources" => {
                  "limits" => {
                    "memory" => "65536Ki"
                  },
                  "requests" => {
                    "memory" => "65536Ki"
                  }
                },
                "ports" => [],
                "volumeMounts" => [{
                  "name" => "tmp-volume",
                  "mountPath" => "/tmp"
                }]
              }],
              "volumes" => [{
                "name" => "tmp-volume",
                "emptyDir" => {}
              }]
            }
          }
        }
      }
      expect(k8s_resource(set, 'Deployment')).to eql(expected_deployment)
    end

    #    it 'creates a correct Ingress resources' do
    #      factory = eval_stacks do
    #        stack "mystack" do
    #          base_service "x", :kubernetes => {'e1' => true} do
    #            self.application = 'ntp'
    #            self.startup_alert_threshold = '10s'
    #          end
    #          app_service "y" do
    #            self.application = 'blah'
    #          end
    #        end
    #        env "e1", :primary_site => 'space' do
    #          instantiate_stack "mystack"
    #          depend_on 'x', 'space'
    #        end
    #      end
    #      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
    #    end
  end
end
