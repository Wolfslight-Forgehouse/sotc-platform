# Changelog

All notable changes to the Swiss OTC Cloud Controller Manager.

## [Unreleased]

### Added
- Cilium CNI migration guide in docs/NETWORKING.md
- Critical OTC networking documentation (VXLAN UDP 8472 requirement)
- CHANGELOG.md

### Changed
- All documentation rewritten in English
- All Go code comments translated to English

## [0.3.0] - 2025-03-05

### Added
- `ip_target_enable: true` for ELB creation (required for IP-based backend members)
- VIP Security Group auto-configuration (add ingress rules for service ports)
- EIP (Elastic IP) support via `otc.io/eip-bandwidth` annotation
- UDP listener support with `UDP_CONNECT` health monitors
- Multi-port service support (multiple listeners/pools per ELB)
- `otc.io/allowed-cidrs` annotation for restricting access
- Dockerfile (multi-stage: golang → alpine)
- Helm chart with RBAC, Secret, Deployment, health probes
- Comprehensive documentation (README.md, DEVELOPMENT.md, NETWORKING.md)

### Fixed
- Health monitor timeout: changed to `timeout=10, delay=5` (Swiss OTC eu-ch2 requires timeout >= delay)
- ELB deletion order: listeners → pools → ELB (OTC returns 409 if dependencies exist)
- Service status uses IP field (not Hostname) for Kubernetes validation
- Security group rule for ELB SNAT range (100.125.0.0/16) on NodePort range

## [0.2.0] - 2025-03-04

### Added
- Complete ELB v3 LoadBalancer lifecycle (create/update/delete)
- Direct HTTP client for OTC ELB v3 API (no SDK dependency)
- IAM token authentication with project scope
- Pool member management (add/remove based on Kubernetes nodes)
- TCP health monitors
- Systemd service deployment

### Fixed
- `vip_subnet_cidr_id` field (Swiss OTC uses this instead of `vip_subnet_id`)
- Default region changed to `eu-ch2` for Swiss OTC

## [0.1.0] - 2025-03-04

### Added
- Initial project structure
- Cloud provider registration for `opentelekomcloud`
- YAML config parser for cloud.conf
- Instances controller (minimal, node metadata)
- LoadBalancer interface skeleton
