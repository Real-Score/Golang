package main

deny[msg] {
  input.kind == "Pod"
  container := input.spec.containers[_]
  container.securityContext.runAsNonRoot != true
  msg := sprintf("Container %v must not run as root", [container.name])
}
