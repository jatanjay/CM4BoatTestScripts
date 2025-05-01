# IP Scanner Script
# This script scans the local network and saves results to a text file

# Function to test if a port is open
function Test-Port {
    param (
        [string]$computer,
        [int]$port,
        [int]$timeout = 5
    )
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $tcp.BeginConnect($computer, $port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($timeout, $true)
        if ($success) {
            return "Open"
        }
        else {
            return "Closed"
        }
    }
    catch {
        return "Closed"
    }
    finally {
        $tcp.Close()
    }
}

# Function to get MAC address
function Get-MACAddress {
    param (
        [string]$ip
    )
    try {
        $arp = arp -a $ip
        if ($arp -match '([0-9A-F]{2}(?:[:-][0-9A-F]{2}){5})') {
            return $matches[0]
        }
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

# Function to get vendor from MAC address
function Get-VendorFromMAC {
    param (
        [string]$mac
    )
    try {
        $mac = $mac -replace '[:-]', ''
        $mac = $mac.Substring(0, 6)
        $url = "https://api.macvendors.com/$mac"
        $response = Invoke-RestMethod -Uri $url -Method Get
        return $response
    }
    catch {
        return "Unknown"
    }
}

# Function to get hostname from IP
function Get-HostnameFromIP {
    param (
        [string]$ip
    )
    try {
        $hostname = [System.Net.Dns]::GetHostEntry($ip).HostName
        return $hostname
    }
    catch {
        return "Unknown"
    }
}

# Get local network information
$route = Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Select-Object -First 1
$gateway = $route.NextHop
$gatewayParts = $gateway -split '\.'
$networkPrefix = (($gatewayParts[0..2] -join '.') + '.')

Write-Host "Starting network scan..."
Write-Host "Network prefix: $networkPrefix"
Write-Host "Scanning IPs from $($networkPrefix)1 to $($networkPrefix)254"

# Create array to store results
$results = @()

# Scan the network
for ($i = 1; $i -le 254; $i++) {
    $ip = "$networkPrefix$i"
    Write-Host "Scanning $ip..." -NoNewline
    
    # Test if host is up
    $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet
    if ($ping) {
        Write-Host " [UP]" -ForegroundColor Green
        
        # Get host information
        $mac = Get-MACAddress -ip $ip
        $vendor = Get-VendorFromMAC -mac $mac
        $hostname = Get-HostnameFromIP -ip $ip
        
        # Test common ports
        $ports = @{
            HTTP = 80
            HTTPS = 443
            SMB = 445
            RDP = 3389
        }
        
        $portStatus = @{}
        foreach ($port in $ports.GetEnumerator()) {
            $portStatus[$port.Key] = Test-Port -computer $ip -port $port.Value
        }
        
        # Add to results
        $results += [PSCustomObject]@{
            IPAddress = $ip
            HostName = $hostname
            MACAddress = $mac
            Vendor = $vendor
            HTTP = $portStatus.HTTP
            HTTPS = $portStatus.HTTPS
            SMB = $portStatus.SMB
            RDP = $portStatus.RDP
        }
    } else {
        Write-Host " [DOWN]" -ForegroundColor Red
    }
}

# Save results to file
$outputFile = "IP_Scan_Results.txt"
$tableContent = "IP Address`tHost Name`tMAC Address`tVendor`tHTTP`tHTTPS`tSMB`tRDP`n"
$tableContent += "----------`t----------`t-----------`t------`t----`t-----`t---`t---`n"

foreach ($result in $results) {
    $tableContent += "$($result.IPAddress)`t$($result.HostName)`t$($result.MACAddress)`t$($result.Vendor)`t$($result.HTTP)`t$($result.HTTPS)`t$($result.SMB)`t$($result.RDP)`n"
}

$tableContent | Out-File -FilePath $outputFile -Encoding UTF8 -Force

Write-Host "`nScan complete! Results saved to $outputFile"
Write-Host "Found $($results.Count) active hosts" 