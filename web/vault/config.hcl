# Vault Dev Server Configuration
# DO NOT use this in production - dev mode only

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8201"
  tls_disable = "true"
}

ui = false

# Default lease duration
default_lease_ttl = "768h"
max_lease_ttl = "768h"
