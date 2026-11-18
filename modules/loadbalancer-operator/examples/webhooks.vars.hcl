# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# The controller and the webhooks in containers, proxies in containers,
# the tokens of the classes in a namespace of their own, a CA for the
# webhooks, and an admission policy that only warns.
driver                  = "docker"
image                   = "registry.example.com/norca/norca-loadbalancer:0.4.0"
proxy_driver            = "docker"
proxy_image             = "registry.example.com/norca/norca-loadbalancer-proxy:0.4.0"
class_token_namespace   = "providers"
webhook_enabled         = true
webhook_url             = "https://lb-webhook.service.norca:8443/"
webhook_ca_cert         = "-----BEGIN CERTIFICATE-----\nMIIBwebhook\n-----END CERTIFICATE-----\n"
classes                 = ["nomad", "hcloud-fsn1"]
default_class           = "hcloud-fsn1"
admission_policy_action = "warn"
