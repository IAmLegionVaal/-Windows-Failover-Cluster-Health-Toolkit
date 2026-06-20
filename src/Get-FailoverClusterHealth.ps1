[CmdletBinding()]
param(
    [Parameter()]
    [string]$ClusterName,

    [Parameter()]
    [ValidateRange(1,720)]
    [int]$Hours = 72,

    [Parameter()]
    [switch]$RunValidation,

    [Parameter()]
    [string]$OutputPath = (Join-Path $PWD ("Failover-Cluster-Health-{0:yyyyMMdd_HHmmss}" -f (Get-Date)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$ErrorLog = Join-Path $OutputPath 'command-errors.log'

function Invoke-Safe {
    param([scriptblock]$ScriptBlock,[string]$Label)
    try { & $ScriptBlock }
    catch { "[$(Get-Date -Format o)] $Label :: $($_.Exception.Message)" | Add-Content $ErrorLog; $null }
}

if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
    throw 'The FailoverClusters PowerShell module is not installed.'
}
Import-Module FailoverClusters -ErrorAction Stop

$cluster = Invoke-Safe -Label 'Cluster discovery' -ScriptBlock {
    if ($ClusterName) { Get-Cluster -Name $ClusterName -ErrorAction Stop }
    else { Get-Cluster -ErrorAction Stop }
}
if (-not $cluster) { throw 'Unable to connect to a failover cluster.' }
$resolvedClusterName = $cluster.Name

$clusterInfo = [pscustomobject]@{
    Name = $cluster.Name
    Domain = $cluster.Domain
    Description = $cluster.Description
    FunctionalLevel = $cluster.ClusterFunctionalLevel
    DynamicQuorum = $cluster.DynamicQuorum
    CrossSubnetDelay = $cluster.CrossSubnetDelay
    CrossSubnetThreshold = $cluster.CrossSubnetThreshold
    SameSubnetDelay = $cluster.SameSubnetDelay
    SameSubnetThreshold = $cluster.SameSubnetThreshold
    QuarantineThreshold = $cluster.QuarantineThreshold
}
$clusterInfo | Export-Csv (Join-Path $OutputPath 'cluster.csv') -NoTypeInformation -Encoding UTF8

$nodes = @(Get-ClusterNode -Cluster $resolvedClusterName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        State = $_.State
        NodeWeight = $_.NodeWeight
        DynamicWeight = $_.DynamicWeight
        DrainStatus = $_.DrainStatus
        StatusInformation = $_.StatusInformation
        MajorVersion = $_.MajorVersion
        MinorVersion = $_.MinorVersion
        BuildNumber = $_.BuildNumber
    }
})
$nodes | Export-Csv (Join-Path $OutputPath 'nodes.csv') -NoTypeInformation -Encoding UTF8

$groups = @(Get-ClusterGroup -Cluster $resolvedClusterName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        GroupType = $_.GroupType
        State = $_.State
        OwnerNode = [string]$_.OwnerNode
        Priority = $_.Priority
        AutoFailbackType = $_.AutoFailbackType
        FailoverThreshold = $_.FailoverThreshold
        FailoverPeriod = $_.FailoverPeriod
    }
})
$groups | Export-Csv (Join-Path $OutputPath 'cluster-groups.csv') -NoTypeInformation -Encoding UTF8

$resources = @(Get-ClusterResource -Cluster $resolvedClusterName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        ResourceType = $_.ResourceType
        State = $_.State
        OwnerGroup = [string]$_.OwnerGroup
        OwnerNode = [string]$_.OwnerNode
        IsCoreResource = $_.IsCoreResource
        RestartAction = $_.RestartAction
        RestartThreshold = $_.RestartThreshold
        RestartPeriod = $_.RestartPeriod
    }
})
$resources | Export-Csv (Join-Path $OutputPath 'resources.csv') -NoTypeInformation -Encoding UTF8

$networks = @(Get-ClusterNetwork -Cluster $resolvedClusterName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        State = $_.State
        Address = $_.Address
        AddressMask = $_.AddressMask
        Role = $_.Role
        Metric = $_.Metric
        AutoMetric = $_.AutoMetric
        Description = $_.Description
    }
})
$networks | Export-Csv (Join-Path $OutputPath 'networks.csv') -NoTypeInformation -Encoding UTF8

$interfaces = @(Get-ClusterNetworkInterface -Cluster $resolvedClusterName -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Node = [string]$_.Node
        Network = [string]$_.Network
        Adapter = $_.Adapter
        Address = $_.Address
        State = $_.State
    }
})
$interfaces | Export-Csv (Join-Path $OutputPath 'network-interfaces.csv') -NoTypeInformation -Encoding UTF8

$quorum = Invoke-Safe -Label 'Quorum' -ScriptBlock { Get-ClusterQuorum -Cluster $resolvedClusterName }
$quorum | Select-Object Cluster,QuorumResource,QuorumType | Export-Csv (Join-Path $OutputPath 'quorum.csv') -NoTypeInformation -Encoding UTF8

$csvRows = New-Object System.Collections.Generic.List[object]
$csvs = Invoke-Safe -Label 'Cluster Shared Volumes' -ScriptBlock { Get-ClusterSharedVolume -Cluster $resolvedClusterName }
foreach ($csv in @($csvs)) {
    foreach ($partition in @($csv.SharedVolumeInfo.Partition)) {
        $csvRows.Add([pscustomobject]@{
            Name = $csv.Name
            State = $csv.State
            OwnerNode = [string]$csv.OwnerNode
            FriendlyVolumeName = $csv.SharedVolumeInfo.FriendlyVolumeName
            PartitionName = $partition.Name
            FileSystem = $partition.FileSystem
            SizeGB = if ($partition.Size) { [math]::Round($partition.Size/1GB,2) } else { $null }
            FreeSpaceGB = if ($partition.FreeSpace) { [math]::Round($partition.FreeSpace/1GB,2) } else { $null }
            PercentFree = if ($partition.Size) { [math]::Round(($partition.FreeSpace/$partition.Size)*100,2) } else { $null }
            RedirectedAccess = $csv.SharedVolumeInfo.RedirectedAccess
            BlockRedirectedIOReason = $csv.SharedVolumeInfo.BlockRedirectedIOReason
        })
    }
}
$csvRows | Export-Csv (Join-Path $OutputPath 'cluster-shared-volumes.csv') -NoTypeInformation -Encoding UTF8

$storagePools = Invoke-Safe -Label 'Storage pools' -ScriptBlock {
    Get-StoragePool -ErrorAction Stop | Select-Object FriendlyName,HealthStatus,OperationalStatus,IsPrimordial,Size,AllocatedSize
}
$storagePools | Export-Csv (Join-Path $OutputPath 'storage-pools.csv') -NoTypeInformation -Encoding UTF8
$physicalDisks = Invoke-Safe -Label 'Physical disks' -ScriptBlock {
    Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName,SerialNumber,MediaType,CanPool,HealthStatus,OperationalStatus,Size,Usage
}
$physicalDisks | Export-Csv (Join-Path $OutputPath 'physical-disks.csv') -NoTypeInformation -Encoding UTF8
$virtualDisks = Invoke-Safe -Label 'Virtual disks' -ScriptBlock {
    Get-VirtualDisk -ErrorAction Stop | Select-Object FriendlyName,ResiliencySettingName,HealthStatus,OperationalStatus,Size,FootprintOnPool
}
$virtualDisks | Export-Csv (Join-Path $OutputPath 'virtual-disks.csv') -NoTypeInformation -Encoding UTF8

$startTime = (Get-Date).AddHours(-$Hours)
$events = New-Object System.Collections.Generic.List[object]
foreach ($logName in @('Microsoft-Windows-FailoverClustering/Operational','System')) {
    $items = Invoke-Safe -Label "Events $logName" -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName=$logName; StartTime=$startTime } -ErrorAction Stop |
            Where-Object { $logName -ne 'System' -or $_.ProviderName -match 'FailoverClustering|ClusSvc|Microsoft-Windows-Storage' } |
            Select-Object TimeCreated,Id,LevelDisplayName,ProviderName,MachineName,Message
    }
    foreach ($item in @($items)) {
        if ($item) {
            $events.Add([pscustomobject]@{
                LogName=$logName
                TimeCreated=$item.TimeCreated
                Id=$item.Id
                Level=$item.LevelDisplayName
                Provider=$item.ProviderName
                MachineName=$item.MachineName
                Message=$item.Message
            })
        }
    }
}
$events | Export-Csv (Join-Path $OutputPath 'cluster-events.csv') -NoTypeInformation -Encoding UTF8

$validationSummary = $null
if ($RunValidation) {
    $validationDir = Join-Path $OutputPath 'cluster-validation'
    New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
    $validation = Invoke-Safe -Label 'Test-Cluster validation' -ScriptBlock {
        Test-Cluster -Cluster $resolvedClusterName -ReportName (Join-Path $validationDir 'ValidationReport') -ErrorAction Stop
    }
    $validationSummary = [pscustomobject]@{
        Requested = $true
        Completed = [bool]$validation
        ReportPath = $validationDir
        Note = 'Review the complete Microsoft cluster validation report before making changes.'
    }
    $validationSummary | Export-Csv (Join-Path $OutputPath 'validation-summary.csv') -NoTypeInformation -Encoding UTF8
}

$summary = [pscustomobject]@{
    CollectedAt = (Get-Date).ToString('o')
    ClusterName = $resolvedClusterName
    FunctionalLevel = $cluster.ClusterFunctionalLevel
    QuorumType = if ($quorum) { $quorum.QuorumType } else { $null }
    QuorumResource = if ($quorum) { [string]$quorum.QuorumResource } else { $null }
    NodeCount = $nodes.Count
    NodesDownOrPaused = @($nodes | Where-Object { $_.State -notin @('Up','Joining') }).Count
    GroupCount = $groups.Count
    GroupsNotOnline = @($groups | Where-Object State -ne 'Online').Count
    ResourceCount = $resources.Count
    ResourcesNotOnline = @($resources | Where-Object State -ne 'Online').Count
    NetworkCount = $networks.Count
    NetworksNotUp = @($networks | Where-Object State -ne 'Up').Count
    CsvCount = $csvRows.Count
    CsvRedirectedAccess = @($csvRows | Where-Object RedirectedAccess).Count
    CsvBelow15PercentFree = @($csvRows | Where-Object { $null -ne $_.PercentFree -and $_.PercentFree -lt 15 }).Count
    UnhealthyPhysicalDisks = @($physicalDisks | Where-Object HealthStatus -ne 'Healthy').Count
    RecentClusterEvents = $events.Count
    RecentErrorOrCriticalEvents = @($events | Where-Object { $_.Level -in @('Error','Critical') }).Count
    ClusterValidationRequested = [bool]$RunValidation
}
$summary | Export-Csv (Join-Path $OutputPath 'summary.csv') -NoTypeInformation -Encoding UTF8
$summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputPath 'summary.json') -Encoding UTF8

$style = '<style>body{font-family:Segoe UI,Arial;margin:28px;color:#172033}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d5dde7;padding:7px;text-align:left}th{background:#eaf2f8}h1,h2{color:#0b3558}</style>'
$body = @()
$body += $summary | ConvertTo-Html -Fragment -PreContent '<h2>Summary</h2>'
$body += $nodes | ConvertTo-Html -Fragment -PreContent '<h2>Nodes</h2>'
$body += $groups | ConvertTo-Html -Fragment -PreContent '<h2>Clustered Roles and Groups</h2>'
$body += $resources | ConvertTo-Html -Fragment -PreContent '<h2>Resources</h2>'
$body += $networks | ConvertTo-Html -Fragment -PreContent '<h2>Networks</h2>'
$body += $csvRows | ConvertTo-Html -Fragment -PreContent '<h2>Cluster Shared Volumes</h2>'
$body += $events | Select-Object -First 250 | ConvertTo-Html -Fragment -PreContent '<h2>Recent Events</h2>'
$body += '<p>Default collection is read-only. Cluster validation runs only when explicitly requested.</p>'
ConvertTo-Html -Title 'Failover Cluster Health' -Head $style -Body $body | Set-Content (Join-Path $OutputPath 'Failover-Cluster-Health.html') -Encoding UTF8

Write-Host "Failover cluster health collection completed: $OutputPath"
