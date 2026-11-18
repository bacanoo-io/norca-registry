variable "datacenters" {
  type    = list(string)
  default = ["*"]
}

variable "node_pool" {
  type    = string
  default = ""
}

variable "spread_over" {
  type        = string
  default     = "datacenter"
  description = "What the instances are spread over: datacenter, node, or empty for none."

  validation {
    one_of = ["", "datacenter", "node"]
  }
}

variable "image" {
  type    = string
  default = ""
}

variable "node" {
  type        = string
  default     = ""
  description = "The node (node.unique.name) a job is pinned to; empty for any."
}

variable "constraints" {
  type = list(object({
    attribute = string
    operator  = string
    value     = string
  }))
  default     = []
  description = "Extra constraints of a job; an empty value is left out."
}

variable "image_digest" {
  type    = string
  default = ""
}
