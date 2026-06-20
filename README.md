# Windows Failover Cluster Health Toolkit

A read-only PowerShell toolkit for collecting Windows Server Failover Clustering health, node, network, quorum, storage, role, event, and validation evidence.

## Features

- Cluster identity, functional level, witness, and quorum configuration
- Node state, version, dynamic weight, and vote inventory
- Clustered roles, groups, resources, owners, and failed-resource evidence
- Cluster network and interface configuration
- Cluster Shared Volume state, ownership, capacity, and redirected-access indicators
- Storage pool, physical disk, and virtual disk context where available
- Recent failover-clustering and system events
- Optional `Test-Cluster` execution only when explicitly requested
- CSV, JSON, HTML, and text outputs

## Usage

Run from an elevated PowerShell console on a cluster node or approved management host:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\Get-FailoverClusterHealth.ps1
```

Target a named cluster:

```powershell
.\src\Get-FailoverClusterHealth.ps1 -ClusterName CLUSTER01 -Hours 72
```

Run cluster validation only during an approved maintenance or assessment window:

```powershell
.\src\Get-FailoverClusterHealth.ps1 -ClusterName CLUSTER01 -RunValidation
```

## Safety

Default collection is read-only. It does not move roles, restart nodes, change quorum, modify networks, repair storage, or alter cluster configuration. `Test-Cluster` is disabled unless `-RunValidation` is supplied because validation can generate load and operational events.

## Requirements

- Windows Server or a management workstation with Failover Clustering PowerShell tools
- Appropriate read permissions to the cluster
- Elevated permissions for complete event and validation evidence

## Validation

Test against a healthy lab cluster, a paused node, an offline resource, a CSV in redirected mode, and a non-clustered host to confirm graceful failure.

## Author

Dewald Pretorius — L2 IT Support Engineer
