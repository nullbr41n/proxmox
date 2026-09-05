resource "kubernetes_namespace_v1" "vpn" {
  metadata {
    name = var.vpn_namespace
  }
}

# ── VPN DNS ──────────────────────────────────────────────────────────────────
# Dedicated CoreDNS instance owned entirely by this stage.
# Resolves *.intra_domain → ingress IP; forwards everything else to OPNsense.
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
              answer "{{ .Name }} 60 IN A ${var.npm_ip != "" ? var.npm_ip : var.ingress_ip}"
          }
          cache 30
      }
      %{for domain in var.npm_domains~}

      ${domain} {
          hosts {
              ${var.npm_ip} ${domain}
          }
          cache 30
      }
      %{endfor~}

      . {
          health :8080
          ready  :8181
          forward . 10.10.11.254
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
        annotations = {
          "nullbrain.com/coredns-config-hash" = sha256(kubernetes_config_map_v1.coredns_vpn.data["Corefile"])
        }
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

    # Recreate terminates the old pod before starting the new one.
    # Required for a RWO PVC — RollingUpdate would deadlock waiting
    # for the volume to detach before it can attach to the new pod.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "wg-easy" }
    }

    template {
      metadata {
        labels = { app = "wg-easy" }
      }

      spec {
        # Rocky Linux 9 (RHEL 9) defaults to nftables; iptable_nat is present
        # but not auto-loaded. wg-quick uses legacy iptables for NAT, so the
        # module must be loaded into the host kernel before wg-easy starts.
        init_container {
          name    = "init-modules"
          image   = "busybox:1.36"
          command = ["sh", "-c", "modprobe iptable_nat"]

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "lib-modules"
            mount_path = "/lib/modules"
            read_only  = true
          }
        }

        container {
          name  = "wg-easy"
          image = "ghcr.io/wg-easy/wg-easy:${var.wg_easy_image_tag}"

          env {
            name  = "WG_HOST"
            value = var.wg_easy_host
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

        volume {
          name = "lib-modules"
          host_path {
            path = "/lib/modules"
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
