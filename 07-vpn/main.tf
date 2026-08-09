resource "kubernetes_namespace_v1" "vpn" {
  metadata {
    name = var.vpn_namespace
  }
}

# ── VPN DNS ──────────────────────────────────────────────────────────────────
# Dedicated CoreDNS instance owned entirely by this stage.
# Resolves *.intra_domain → ingress IP; forwards everything else to public DNS.
# Runs 2 replicas so it survives node loss without touching cluster CoreDNS.

resource "kubernetes_config_map_v1" "coredns_vpn" {
  metadata {
    name      = "coredns-vpn"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  data = {
    Corefile = <<-COREFILE
      ${var.intra_domain} {
          template IN A {
              answer "{{ .Name }} 60 IN A ${var.ingress_ip}"
          }
          cache 30
      }

      . {
          health :8080
          ready  :8181
          forward . 1.1.1.1 8.8.8.8
          cache 300
          errors
      }
    COREFILE
  }
}

resource "kubernetes_deployment_v1" "coredns_vpn" {
  metadata {
    name      = "coredns-vpn"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "coredns-vpn" }
    }

    template {
      metadata {
        labels = { app = "coredns-vpn" }
      }

      spec {
        container {
          name  = "coredns"
          image = var.coredns_image
          args  = ["-conf", "/etc/coredns/Corefile"]

          port {
            name           = "dns-udp"
            container_port = 53
            protocol       = "UDP"
          }

          port {
            name           = "dns-tcp"
            container_port = 53
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8181
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/coredns"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.coredns_vpn.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "coredns_vpn" {
  metadata {
    name      = "coredns-vpn"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  spec {
    selector         = { app = "coredns-vpn" }
    load_balancer_ip = var.coredns_vpn_ip
    type             = "LoadBalancer"

    port {
      name        = "dns-udp"
      protocol    = "UDP"
      port        = 53
      target_port = 53
    }

    port {
      name        = "dns-tcp"
      protocol    = "TCP"
      port        = 53
      target_port = 53
    }
  }

  depends_on = [kubernetes_deployment_v1.coredns_vpn]
}

# ── wg-easy ───────────────────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "wg_easy" {
  metadata {
    name      = "wg-easy"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  data = {
    password_hash = var.wg_easy_password_hash
  }
}

resource "kubernetes_persistent_volume_claim_v1" "wg_easy" {
  metadata {
    name      = "wg-easy"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  # lvm-4tb uses WaitForFirstConsumer — PVC binds when the pod is scheduled.
  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = { storage = "100Mi" }
    }
  }
}

resource "kubernetes_deployment_v1" "wg_easy" {
  metadata {
    name      = "wg-easy"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "wg-easy" }
    }

    template {
      metadata {
        labels = { app = "wg-easy" }
      }

      spec {
        container {
          name  = "wg-easy"
          image = "ghcr.io/wg-easy/wg-easy:${var.wg_easy_image_tag}"

          env {
            name  = "WG_HOST"
            value = var.wg_easy_ip
          }

          env {
            name = "PASSWORD_HASH"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wg_easy.metadata[0].name
                key  = "password_hash"
              }
            }
          }

          env {
            name  = "WG_DEFAULT_DNS"
            value = var.coredns_vpn_ip
          }

          env {
            name  = "WG_ALLOWED_IPS"
            value = var.wg_easy_allowed_ips
          }

          env {
            name  = "WG_DEFAULT_ADDRESS"
            value = var.wg_easy_vpn_cidr
          }

          port {
            name           = "wireguard"
            container_port = 51820
            protocol       = "UDP"
          }

          port {
            name           = "ui"
            container_port = 51821
            protocol       = "TCP"
          }

          # Privileged is required: wg-quick needs to load iptable_nat and
          # set up NAT rules, which NET_ADMIN alone does not allow in a container.
          security_context {
            privileged = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/etc/wireguard"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.wg_easy.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.wg_easy]
}

resource "kubernetes_service_v1" "wg_easy" {
  metadata {
    name      = "wg-easy"
    namespace = kubernetes_namespace_v1.vpn.metadata[0].name
  }

  spec {
    selector         = { app = "wg-easy" }
    load_balancer_ip = var.wg_easy_ip
    type             = "LoadBalancer"

    port {
      name        = "wireguard"
      protocol    = "UDP"
      port        = 51820
      target_port = 51820
    }

    port {
      name        = "ui"
      protocol    = "TCP"
      port        = 51821
      target_port = 51821
    }
  }

  depends_on = [kubernetes_deployment_v1.wg_easy]
}
