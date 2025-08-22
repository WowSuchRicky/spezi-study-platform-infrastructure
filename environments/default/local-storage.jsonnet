local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.29/main.libsonnet';

{
  // Local Storage Class for Kind development
  'local-storage-class': k.storage.v1.storageClass.new('local-path') +
    k.storage.v1.storageClass.withProvisioner('rancher.io/local-path') +
    k.storage.v1.storageClass.withVolumeBindingMode('WaitForFirstConsumer') +
    k.storage.v1.storageClass.withReclaimPolicy('Delete') +
    k.storage.v1.storageClass.withAllowVolumeExpansion(true) +
    k.storage.v1.storageClass.metadata.withAnnotations({
      'storageclass.kubernetes.io/is-default-class': 'true',
    }),

  // Local Path Provisioner Namespace
  'local-path-storage-namespace': k.core.v1.namespace.new('local-path-storage'),

  // ServiceAccount for Local Path Provisioner
  'local-path-provisioner-service-account': k.core.v1.serviceAccount.new('local-path-provisioner-service-account') +
    k.core.v1.serviceAccount.mixin.metadata.withNamespace('local-path-storage'),

  // ClusterRole for Local Path Provisioner
  'local-path-provisioner-role': k.rbac.v1.clusterRole.new('local-path-provisioner-role') +
    k.rbac.v1.clusterRole.withRules([
      {
        apiGroups: [''],
        resources: ['nodes', 'persistentvolumeclaims', 'configmaps'],
        verbs: ['get', 'list', 'watch']
      },
      {
        apiGroups: [''],
        resources: ['endpoints', 'persistentvolumes', 'pods'],
        verbs: ['*']
      },
      {
        apiGroups: [''],
        resources: ['events'],
        verbs: ['create', 'patch']
      },
      {
        apiGroups: ['storage.k8s.io'],
        resources: ['storageclasses'],
        verbs: ['get', 'list', 'watch']
      }
    ]),

  // ClusterRoleBinding for Local Path Provisioner
  'local-path-provisioner-bind': {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'local-path-provisioner-bind'
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'local-path-provisioner-role'
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'local-path-provisioner-service-account',
        namespace: 'local-path-storage'
      }
    ]
  },

  // ConfigMap for Local Path Provisioner
  'local-path-config': k.core.v1.configMap.new('local-path-config') +
    k.core.v1.configMap.mixin.metadata.withNamespace('local-path-storage') +
    k.core.v1.configMap.withData({
      'config.json': std.manifestJsonEx({
        'nodePathMap': [
          {
            'node': 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
            'paths': ['/opt/local-path-provisioner']
          }
        ]
      }, '  '),
      'setup': |||
        #!/bin/sh
        set -eu
        mkdir -m 0777 -p "$VOL_DIR"
      |||,
      'teardown': |||
        #!/bin/sh
        set -eu
        rm -rf "$VOL_DIR"
      |||,
      'helperPod.yaml': |||
        apiVersion: v1
        kind: Pod
        metadata:
          name: helper-pod
        spec:
          containers:
          - name: helper-pod
            image: busybox
            imagePullPolicy: IfNotPresent
      |||
    }),

  // Deployment for Local Path Provisioner
  'local-path-provisioner': {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: 'local-path-provisioner',
      namespace: 'local-path-storage'
    },
    spec: {
      replicas: 1,
      selector: {
        matchLabels: {
          app: 'local-path-provisioner'
        }
      },
      template: {
        metadata: {
          labels: {
            app: 'local-path-provisioner'
          }
        },
        spec: {
          serviceAccount: 'local-path-provisioner-service-account',
          containers: [
            {
              name: 'local-path-provisioner',
              image: 'rancher/local-path-provisioner:v0.0.24',
              command: ['local-path-provisioner', '--debug', 'start', '--config', '/etc/config/config.json'],
              env: [
                {
                  name: 'POD_NAMESPACE',
                  valueFrom: {
                    fieldRef: {
                      fieldPath: 'metadata.namespace'
                    }
                  }
                }
              ],
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 1000
              },
              volumeMounts: [
                {
                  name: 'config-volume',
                  mountPath: '/etc/config'
                }
              ]
            }
          ],
          volumes: [
            {
              name: 'config-volume',
              configMap: {
                name: 'local-path-config'
              }
            }
          ],
          tolerations: [
            {
              key: 'node-role.kubernetes.io/control-plane',
              operator: 'Exists',
              effect: 'NoSchedule'
            }
          ],
          nodeSelector: {
            'kubernetes.io/os': 'linux'
          }
        }
      }
    }
  },
}