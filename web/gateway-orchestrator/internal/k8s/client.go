package k8s

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/kubernetes"

	"trinity-agi/gateway-orchestrator/internal/db"
)

// Client wraps the Kubernetes clientset and provides resource operations.
type Client struct {
	clientset kubernetes.Interface
	namespace string
}

// NewClient creates a new Kubernetes client wrapper.
func NewClient(clientset kubernetes.Interface, namespace string) *Client {
	return &Client{
		clientset: clientset,
		namespace: namespace,
	}
}

// sanitizeName normalizes a name for use as a Kubernetes resource name.
var invalidChars = regexp.MustCompile(`[^a-z0-9-]`)

func sanitizeName(name string) string {
	s := strings.ToLower(name)
	s = invalidChars.ReplaceAllString(s, "-")
	if len(s) > 50 {
		s = s[:50]
	}
	return strings.Trim(s, "-")
}

// ResourceName returns the canonical K8s resource name for an OpenClaw instance.
func ResourceName(name string) string {
	return fmt.Sprintf("openclaw-%s", sanitizeName(name))
}

// resourceLabels returns the standard labels for an OpenClaw instance.
func resourceLabels(openclawID, name string) map[string]string {
	return map[string]string{
		"trinity.ai/openclaw-id":  openclawID,
		"trinity.ai/openclaw":     sanitizeName(name),
		"app.kubernetes.io/name":  "openclaw-instance",
	}
}

// ── Create Resources ────────────────────────────────────────────────────

// CreateOpenClawSecret creates a Kubernetes Secret containing the gateway token.
func (c *Client) CreateOpenClawSecret(ctx context.Context, oc *db.OpenClaw, resName string) error {
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      resName,
			Namespace: c.namespace,
			Labels:    resourceLabels(oc.ID, oc.Name),
		},
		Type: corev1.SecretTypeOpaque,
		StringData: map[string]string{
			"OPENCLAW_GATEWAY_TOKEN": oc.GatewayToken,
		},
	}
	_, err := c.clientset.CoreV1().Secrets(c.namespace).Create(ctx, secret, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return fmt.Errorf("create secret %s: %w", resName, err)
	}
	return nil
}

// CreateOpenClawConfigMap creates a ConfigMap with the openclaw.json config.
func (c *Client) CreateOpenClawConfigMap(ctx context.Context, oc *db.OpenClaw, resName string) error {
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      resName,
			Namespace: c.namespace,
			Labels:    resourceLabels(oc.ID, oc.Name),
		},
		Data: map[string]string{
			"openclaw.json": `{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": {
      "mode": "token"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "sandbox": {
        "mode": "off",
        "scope": "agent"
      }
    }
  },
  "tools": {
    "profile": "full",
    "web": {
      "search": { "enabled": true },
      "fetch": { "enabled": true }
    }
  },
  "browser": {
    "enabled": true,
    "headless": true,
    "noSandbox": true
  }
}`,
		},
	}
	_, err := c.clientset.CoreV1().ConfigMaps(c.namespace).Create(ctx, cm, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return fmt.Errorf("create configmap %s: %w", resName, err)
	}
	return nil
}

// CreateOpenClawPVC creates a PersistentVolumeClaim for instance data.
func (c *Client) CreateOpenClawPVC(ctx context.Context, oc *db.OpenClaw, resName, storageClass string) error {
	pvc := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      resName,
			Namespace: c.namespace,
			Labels:    resourceLabels(oc.ID, oc.Name),
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes:      []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
			StorageClassName: &storageClass,
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse("5Gi"),
				},
			},
		},
	}
	_, err := c.clientset.CoreV1().PersistentVolumeClaims(c.namespace).Create(ctx, pvc, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return fmt.Errorf("create pvc %s: %w", resName, err)
	}
	return nil
}

// CreateOpenClawService creates a ClusterIP Service for the instance.
func (c *Client) CreateOpenClawService(ctx context.Context, oc *db.OpenClaw, resName string) error {
	labels := resourceLabels(oc.ID, oc.Name)
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      resName,
			Namespace: c.namespace,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Type:     corev1.ServiceTypeClusterIP,
			Selector: labels,
			Ports: []corev1.ServicePort{
				{
					Name:       "gateway",
					Port:       18789,
					TargetPort: intstr.FromInt32(18789),
					Protocol:   corev1.ProtocolTCP,
				},
			},
		},
	}
	_, err := c.clientset.CoreV1().Services(c.namespace).Create(ctx, svc, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return fmt.Errorf("create service %s: %w", resName, err)
	}
	return nil
}

// CreateOpenClawDeployment creates the Deployment for an OpenClaw instance.
func (c *Client) CreateOpenClawDeployment(ctx context.Context, oc *db.OpenClaw, resName, image, storageClass string) error {
	replicas := int32(1)
	labels := resourceLabels(oc.ID, oc.Name)

	deployment := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      resName,
			Namespace: c.namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Strategy: appsv1.DeploymentStrategy{
				Type: appsv1.RecreateDeploymentStrategyType,
			},
			Selector: &metav1.LabelSelector{
				MatchLabels: labels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: labels,
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:    "openclaw",
							Image:   image,
							Command: []string{"/usr/local/bin/bootstrap-openclaw.sh"},
							Args:    []string{"openclaw", "gateway", "--port", "18789", "--bind", "lan", "--allow-unconfigured"},
							Ports: []corev1.ContainerPort{
								{
									Name:          "gateway",
									ContainerPort: 18789,
									Protocol:      corev1.ProtocolTCP,
								},
							},
							Env: []corev1.EnvVar{
								{
									Name: "OPENCLAW_GATEWAY_TOKEN",
									ValueFrom: &corev1.EnvVarSource{
										SecretKeyRef: &corev1.SecretKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: resName},
											Key:                  "OPENCLAW_GATEWAY_TOKEN",
										},
									},
								},
								{Name: "NODE_ENV", Value: "production"},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "data", MountPath: "/home/node/.openclaw"},
								{Name: "config", MountPath: "/home/node/.openclaw/openclaw.json", SubPath: "openclaw.json", ReadOnly: true},
								{Name: "shm", MountPath: "/dev/shm"},
							},
							LivenessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{Path: "/healthz", Port: intstr.FromInt32(18789)},
								},
								InitialDelaySeconds: 10,
								PeriodSeconds:       30,
								TimeoutSeconds:      5,
								FailureThreshold:    3,
							},
							ReadinessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{Path: "/readyz", Port: intstr.FromInt32(18789)},
								},
								InitialDelaySeconds: 5,
								PeriodSeconds:       10,
								TimeoutSeconds:      3,
								FailureThreshold:    3,
							},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceMemory: resource.MustParse("1Gi"),
									corev1.ResourceCPU:    resource.MustParse("500m"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceMemory: resource.MustParse("2Gi"),
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{Name: "data", VolumeSource: corev1.VolumeSource{
							PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{ClaimName: resName},
						}},
						{Name: "config", VolumeSource: corev1.VolumeSource{
							ConfigMap: &corev1.ConfigMapVolumeSource{
								LocalObjectReference: corev1.LocalObjectReference{Name: resName},
							},
						}},
						{Name: "shm", VolumeSource: corev1.VolumeSource{
							EmptyDir: &corev1.EmptyDirVolumeSource{Medium: corev1.StorageMediumMemory},
						}},
					},
				},
			},
		},
	}

	_, err := c.clientset.AppsV1().Deployments(c.namespace).Create(ctx, deployment, metav1.CreateOptions{})
	if err != nil && !errors.IsAlreadyExists(err) {
		return fmt.Errorf("create deployment %s: %w", resName, err)
	}
	return nil
}

// ── Delete Resources ────────────────────────────────────────────────────

// DeleteOpenClawResources removes all Kubernetes resources for an OpenClaw instance.
func (c *Client) DeleteOpenClawResources(ctx context.Context, oc *db.OpenClaw, resName string) error {
	propagation := metav1.DeletePropagationForeground
	delOpts := metav1.DeleteOptions{PropagationPolicy: &propagation}

	for _, fn := range []func() error{
		func() error {
			return c.clientset.AppsV1().Deployments(c.namespace).Delete(ctx, resName, delOpts)
		},
		func() error {
			return c.clientset.CoreV1().Services(c.namespace).Delete(ctx, resName, metav1.DeleteOptions{})
		},
		func() error {
			return c.clientset.CoreV1().PersistentVolumeClaims(c.namespace).Delete(ctx, resName, metav1.DeleteOptions{})
		},
		func() error {
			return c.clientset.CoreV1().ConfigMaps(c.namespace).Delete(ctx, resName, metav1.DeleteOptions{})
		},
		func() error {
			return c.clientset.CoreV1().Secrets(c.namespace).Delete(ctx, resName, metav1.DeleteOptions{})
		},
	} {
		if err := fn(); err != nil && !errors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

// ── Status ──────────────────────────────────────────────────────────────

// GetOpenClawPodStatus returns the phase and readiness of an OpenClaw instance's pod.
func (c *Client) GetOpenClawPodStatus(ctx context.Context, oc *db.OpenClaw) (string, error) {
	labelSelector := fmt.Sprintf("trinity.ai/openclaw-id=%s,app.kubernetes.io/name=openclaw-instance", oc.ID)

	pods, err := c.clientset.CoreV1().Pods(c.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return "", fmt.Errorf("list pods for %s: %w", oc.Name, err)
	}
	if len(pods.Items) == 0 {
		return "no-pods", nil
	}

	pod := pods.Items[0]
	phase := string(pod.Status.Phase)
	for _, cond := range pod.Status.Conditions {
		if cond.Type == corev1.PodReady && cond.Status == corev1.ConditionTrue {
			return phase + "/ready", nil
		}
	}
	return phase + "/not-ready", nil
}
