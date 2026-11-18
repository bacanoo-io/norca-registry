# SPDX-FileCopyrightText: 2026 Norca contributors
# SPDX-License-Identifier: MPL-2.0

# Every namespace with the mock drivers of a test cluster, the tokens of the
# classes in a third namespace.
driver                = "mock_driver"
proxy_driver          = "mock_driver"
watch_namespace       = "*"
class_token_namespace = "providers"
webhook_enabled       = true
webhook_url           = "https://lb-webhook.example.com"
