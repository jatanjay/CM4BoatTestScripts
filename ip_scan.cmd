<# :: Hybrid CMD / Powershell Launcher - Rename file to .CMD to Autolaunch with console settings (Double-Click) - Rename to .PS1 to run as Powershell script without console settings
@ECHO OFF
SET "0=%~f0"&SET "LEGACY={B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"&SET "LETWIN={00000000-0000-0000-0000-000000000000}"&SET "TERMINAL={2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}"&SET "TERMINAL2={E12CFF52-A866-4C77-9A90-F570A7AA2C6B}"
POWERSHELL -nop -c "Get-WmiObject -Class Win32_OperatingSystem | Select -ExpandProperty Caption | Find 'Windows 11'">nul
IF ERRORLEVEL 0 (
	SET isEleven=1
	>nul 2>&1 REG QUERY "HKCU\Console\%%%%Startup" /v DelegationConsole
	IF ERRORLEVEL 1 (
		REG ADD "HKCU\Console\%%%%Startup" /v DelegationConsole /t REG_SZ /d "%LETWIN%" /f>nul
		REG ADD "HKCU\Console\%%%%Startup" /v DelegationTerminal /t REG_SZ /d "%LETWIN%" /f>nul
	)
	FOR /F "usebackq tokens=3" %%# IN (`REG QUERY "HKCU\Console\%%%%Startup" /v DelegationConsole 2^>nul`) DO (
		IF NOT "%%#"=="%LEGACY%" (
			SET "DEFAULTCONSOLE=%%#"
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationConsole /t REG_SZ /d "%LEGACY%" /f>nul
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationTerminal /t REG_SZ /d "%LEGACY%" /f>nul
		)
	)
)
START /MIN "" POWERSHELL -nop -c "iex ([io.file]::ReadAllText('%~f0'))">nul
IF "%isEleven%"=="1" (
	IF DEFINED DEFAULTCONSOLE (
		IF "%DEFAULTCONSOLE%"=="%TERMINAL%" (
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationConsole /t REG_SZ /d "%TERMINAL%" /f>nul
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationTerminal /t REG_SZ /d "%TERMINAL2%" /f>nul
		) ELSE (
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationConsole /t REG_SZ /d "%DEFAULTCONSOLE%" /f>nul
			REG ADD "HKCU\Console\%%%%Startup" /v DelegationTerminal /t REG_SZ /d "%DEFAULTCONSOLE%" /f>nul
		)
	)
)
EXIT
#>if($env:0){$PSCommandPath="$env:0"}
###POWERSHELL BELOW THIS LINE###

# Hide Console - Show GUI Only - Only works for Legacy console
Add-Type -MemberDefinition '[DllImport("User32.dll")]public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' -Namespace Win32 -Name Functions
$closeConsoleUseGUI=[Win32.Functions]::ShowWindow((Get-Process -Id $PID).MainWindowHandle,0)

# Allow Single Instance Only
$AppId = 'Simple IP Scanner'
$singleInstance = $false
$script:SingleInstanceEvent = New-Object Threading.EventWaitHandle $true,([Threading.EventResetMode]::ManualReset),"Global\$AppId",([ref] $singleInstance)
if (-not $singleInstance){
	$shell = New-Object -ComObject Wscript.Shell
	$shell.Popup("$AppId is already running!",0,'ERROR:',0x0) | Out-Null
	Exit
}

# Check if .NET Framework version is at least 3.0, which is required for WPF applications
$frameworks = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse | Get-ItemProperty -Name Version -EA 0 | Where-Object { $_.PSChildName -Match '^(?!S)\p{L}'} | Select-Object -ExpandProperty Version
$highestVersion = $frameworks | ForEach-Object { [version]$_ } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
if ($highestVersion -lt [version]'3.0') {
	$dotnetchecker = New-Object -ComObject Wscript.Shell
	$dotnetchecker.Popup("dotNET 3.0 or higher is required!",0,'ERROR:',0x0) | Out-Null
	Exit
}

# GUI Main Dispatcher
function Update-uiMain(){
	$Main.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Background, [action]{})
}

function Update-Progress {
	param ($value, $text)
	$Progress.Value = $value
	$BarText.Text = $text
	Update-uiMain
}

# Find gateway
$route = Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Select-Object -First 1
$global:gateway = $route.NextHop
$gatewayParts = $global:gateway -split '\.'
$global:gatewayPrefix = (($gatewayParts[0..2] -join '.') + '.')

# Store the original gateway prefix for reset functionality
$originalGatewayPrefix = $global:gatewayPrefix

# Initialize RunspacePool
$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, [System.Environment]::ProcessorCount, $SessionState, $Host)
$RunspacePool.Open()

# Get Host Info
function Get-HostInfo {
	param(
		[string]$gateway,
		[string]$gatewayPrefix,
		[string]$originalGatewayPrefix
	)
	$getHostInfoScriptBlock = {
		param(
			[string]$gateway,
			[string]$gatewayPrefix,
			[string]$originalGatewayPrefix
		)
		# Get Hostname
		$hostName = [System.Net.Dns]::GetHostName()

		# Check internet connection and get external IP
		$ProgressPreference = 'SilentlyContinue'
		try {
			$ncsiCheck = Invoke-RestMethod "http://www.msftncsi.com/ncsi.txt"
			if ($ncsiCheck -eq "Microsoft NCSI") {
				$externalIP = Invoke-RestMethod "http://ifconfig.me/ip"
			} else {
				$externalIP = "No Internet or Redirection"
			}
		} catch {
			$externalIP = "No Internet or Error"
		}
		$ProgressPreference = 'Continue'

		# Use the passed gateway and gatewayPrefix
		$internalIP = (Get-NetIPAddress | Where-Object {
			$_.AddressFamily -eq 'IPv4' -and
			$_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1' -and
			$_.IPAddress -like "$originalGatewayPrefix*"
		}).IPAddress

		# Get current adapter
		$adapter = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
			$_.InterfaceAlias -match 'Ethernet|Wi-Fi' -and
			$_.IPAddress -like "$originalGatewayPrefix*"
		}).InterfaceAlias

		# Get MAC address
		$myMac = (Get-NetAdapter -Name $adapter).MacAddress -replace '-', ':'

		# Get domain
		$domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain

		# Init ARP cache data
		$arpInit = Get-NetNeighbor | Where-Object {($_.State -eq "Reachable" -or $_.State -eq "Stale") -and ($_.IPAddress -like "$gatewayPrefix*") -and -not $_.IPAddress.Contains(':')} | Select-Object -Property IPAddress, LinkLayerAddress

		# Mark empty as unknown
		$variables = @('hostName', 'externalIP', 'internalIP', 'gateway', 'domain')
		foreach ($item in $variables) {
			if (-not (Get-Variable -Name $item -ValueOnly)) {
				Set-Variable -Name $item -Value 'Unknown'
			}
		}

		return @{
			'hostName' = $hostName;
			'externalIP' = $externalIP;
			'internalIP' = $internalIP;
			'gateway' = $gateway;
			'gatewayPrefix' = $gatewayPrefix;
			'adapter' = $adapter;
			'myMac' = $myMac;
			'domain' = $domain;
			'arpInit' = $arpInit;
		}
	}

	$getHostInfoThread = [powershell]::Create().AddScript($getHostInfoScriptBlock)
	$getHostInfoThread.AddArgument($global:gateway)
	$getHostInfoThread.AddArgument($global:gatewayPrefix)
	$getHostInfoThread.AddArgument($originalGatewayPrefix)
	$getHostInfoThread.RunspacePool = $RunspacePool
	$getHostInfoAsync = $getHostInfoThread.BeginInvoke()
	$getHostInfoAsync.AsyncWaitHandle.WaitOne()
	$hostInfoResults = $getHostInfoThread.EndInvoke($getHostInfoAsync)
	$global:hostName = $hostInfoResults.hostName
	$global:externalIP = $hostInfoResults.externalIP
	$global:internalIP = $hostInfoResults.internalIP
	$global:gateway = $hostInfoResults.gateway
	$global:gatewayPrefix = $hostInfoResults.gatewayPrefix
	$global:adapter = $hostInfoResults.adapter
	$global:myMac = $hostInfoResults.myMac
	$global:domain = $hostInfoResults.domain
	$global:arpInit = $hostInfoResults.arpInit
	Update-Progress 0 'Scanning'
	$getHostInfoThread.Dispose()
}

# Send packets across subnet (progress values adjusted for proper display)
function Scan-Subnet {
		$progressCounter = 0

		1..254 | ForEach-Object {
			$progressCounter++
			$percentComplete = [math]::Min([math]::Round(($progressCounter / 240) * 100), 100)
			Test-Connection -ComputerName "$global:gatewayPrefix$_" -Count 1 -AsJob | Out-Null
			if($percentComplete -ge 100){
				Update-Progress -value $percentComplete -text "Listening"
			} else {
				Update-Progress -value $percentComplete -text "Sending Packets"
			}
		}
		Update-Progress -value 100 -text "Listening"
		Get-Job | Wait-Job -ErrorAction Stop | Out-Null
		$results = Get-Job | Receive-Job -ErrorAction Stop
		$global:successfulPings = @($results | Where-Object { $_.StatusCode -eq 0 } | Select-Object -ExpandProperty Address)
		Get-Job | Remove-Job -Force
}

# Create peer list
function List-Machines {
	Update-Progress 0 'Identifying Devices'

	# Convert IP Addresses from string to int by each section
	$arpOutput = $arpInit | Where-Object { $_.IPAddress -match "^\d+\.\d+\.\d+\.\d+$" } | Sort-Object -Property { $ip = $_.IPAddress; [version]($ip) }

	$self = 0
	$myLastOctet = [int]($internalIP -split '\.')[-1]

	# Get Vendor via Mac (thanks to u/mprz)
	$ProgressPreference = 'SilentlyContinue'
	$tryMyVendor = (irm "https://www.macvendorlookup.com/api/v2/$($myMac.Replace(':','').Substring(0,6))" -Method Get).Company
	$ProgressPreference = 'Continue'
	$myVendor = if($tryMyVendor){$tryMyVendor.substring(0, [System.Math]::Min(35, $tryMyVendor.Length))} else {'Unable to Identify'}

	# Cycle through ARP table to populate initial ListView data and start async lookups
	$totalItems = ($arpOutput.Count - 1)

	# First, add all known ARP entries and hostnames
	foreach ($line in $arpOutput) {
		$ip = $line.IPAddress
		$mac = $line.LinkLayerAddress.Replace('-',':')
		$quickNameLookup = ((Resolve-DnsName -Name $ip -DnsOnly -ErrorAction SilentlyContinue).NameHost)
		if(-not $quickNameLookup){$quickNameLookup = 'Resolving...'}
		$name = if ($ip -eq $internalIP) {"$hostName (This Device)"} else {"$quickNameLookup"}
		$vendor = if ($ip -eq $internalIP) {$myVendor} else {'Identifying...'}

		# Determine if the IP was pingable
		$pingResult = $ip -in $global:successfulPings

		# Format and display
		$item = [pscustomobject]@{
			'MACaddress' = $mac;
			'Vendor' = $vendor;
			'IPaddress' = $ip;
			'HostName' = $name;
			'Ping' = $pingResult;
			'PingImage' = Create-GradientEllipse -isPingSuccessful $pingResult
		}
		$listView.Items.Add($item)
	}

	# Now add entries for successful pings not in ARP data, and add self
	$successfulPingsNotInARP = $global:successfulPings | Where-Object { $_ -notin $arpOutput.IPAddress }
	foreach ($ip in $successfulPingsNotInARP) {
		if ($global:gatewayPrefix -ne $originalGatewayPrefix) {
			$mac = 'Unreachable'
		} else {
			$mac = [MacAddressResolver]::GetMacFromIP($ip)
		}
		if ($ip -eq $internalIP) {
			$item = [pscustomobject]@{
				'MACaddress' = $myMac;
				'Vendor' = $myVendor;
				'IPaddress' = $internalIP;
				'HostName' = "$hostName (This Device)";
				'Ping' = $true;
				'PingImage' = Create-GradientEllipse -isPingSuccessful $true
			}
			$listView.Items.Add($item)
		} else {
			$item = [pscustomobject]@{
				'MACaddress' = $mac;
				'Vendor' = $vendor;
				'IPaddress' = $ip;
				'HostName' = 'Resolving...';
				'Ping' = $true;
				'PingImage' = Create-GradientEllipse -isPingSuccessful $true
			}
			$listView.Items.Add($item)
		}
	}

	# Sort ListView items by IP address in ascending order
	$sortedItems = $listView.Items | Sort-Object -Property {[version]$_.IPaddress}
	$listView.Items.Clear()
	$sortedItems | ForEach-Object { $listView.Items.Add($_) }
	$listView.Items.Refresh()

	if ($totalItems -ge 21) {
		$hostNameColumn.Width = 270
	}
	$global:totalCount = $listView.Items.Count
	$TotalListed.Text = "$totalCount devices found"
	Update-uiMain
}

# Background Vendor Lookup
function processVendors {
	$runspace = [runspacefactory]::CreateRunspace()
	$runspace.Open()
	$vendorLookup = [powershell]::Create()
	$vendorLookup.Runspace = $runspace

	$lookupBlock = {
		param ($listView, $internalIP)

		$vendorJobs = @{}

		# Process found devices
		foreach ($item in $listView.Items) {
			$ip = $item.IPaddress
			$mac = $item.MACaddress
			if ($ip -ne $internalIP) {
				if($item.Vendor -eq 'Identifying...'){
					$vendorJob = Start-Job -ScriptBlock {
						param($mac)
						$ProgressPreference = 'SilentlyContinue'
						$response = (irm "https://www.macvendorlookup.com/api/v2/$($mac.Replace(':','').Substring(0,6))" -Method Get)
						$ProgressPreference = 'Continue'
						if([string]::IsNullOrEmpty($response.Company)){
							return $null
						} else {
							return $response
						}
					} -ArgumentList $mac
					$vendorJobs[$ip] = $vendorJob
					do {
						# Limit maximum vendor tasks and process
						foreach ($ipCheck in @($vendorJobs.Keys)) {
							if ($vendorJobs[$ipCheck].State -eq "Completed") {
								$result = Receive-Job -Job $vendorJobs[$ipCheck]
								$vendorResult = if ($result -and $result.Company) {
									$result.Company.substring(0, [System.Math]::Min(30, $result.Company.Length))
								} else {
									'Unable to Identify'
								}
								foreach ($it in $listView.Items) {
									if ($it.IPaddress -eq $ipCheck) {
										$it.Vendor = $vendorResult
									}
								}
								$vendorJobs.Remove($ipCheck)
							}
						}
						Start-Sleep -Milliseconds 50
					} while ($vendorJobs.Count -ge 5)
				}
			}
		}

		# Process remaining tasks
		while ($vendorJobs.Count -ge 1) {
			# Process vendor tasks
			foreach ($ipCheck in @($vendorJobs.Keys)) {
				if ($vendorJobs[$ipCheck].State -eq "Completed") {
					$result = Receive-Job -Job $vendorJobs[$ipCheck]
					$vendorResult = if ($result -and $result.Company) {
						$result.Company.substring(0, [System.Math]::Min(30, $result.Company.Length))
					} else {
						'Unable to Identify'
					}
					foreach ($it in $listView.Items) {
						if ($it.IPaddress -eq $ipCheck) {
							$it.Vendor = $vendorResult
						}
					}
					$vendorJobs.Remove($ipCheck)
				}
			}
			Start-Sleep -Milliseconds 50
		}

		# Clean up jobs
		Remove-Job -Job $vendorJobs.Values -Force
	}

	# Script block params
	$null = $vendorLookup.AddScript($lookupBlock).AddArgument($listView).AddArgument($internalIP)

	$asyncResult = $vendorLookup.BeginInvoke()

	# Cleanup
	$vendorLookup.EndInvoke($asyncResult)
	$vendorLookup.Dispose()
	$runspace.Close()
	$runspace.Dispose()
}

# Background Hostname Lookup
function processHostnames {
	$hostnameLookupThread = [powershell]::Create().AddScript({
		param ($listView, $internalIP, $RunspacePool, $gatewayPrefix, $originalGatewayPrefix)

		$pingItems = @()
		$nonPingItems = @()

		# Separate items into pingable and non-pingable
		foreach ($item in $listView.Items) {
			if ($item.Ping -eq $true -and $item.IPaddress -ne $internalIP) {
				$pingItems += $item
			} elseif ($item.IPaddress -ne $internalIP) {
				$nonPingItems += $item
			}
		}

		# Hostname resolution with timeout
		$timeout = if ($gatewayPrefix -ne $originalGatewayPrefix) { 4500 } else { 3000 }
		$resolveScript = {
			param ($ip, $timeout)
			$dnsTask = [System.Net.Dns]::GetHostEntryAsync($ip)
			$timeoutTask = [System.Threading.Tasks.Task]::Delay($timeout)

			$task = [System.Threading.Tasks.Task]::WhenAny($dnsTask, $timeoutTask)
			$task.Wait()
			$result = $task.Result

			if ($result -eq $dnsTask -and $dnsTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
				return [PSCustomObject]@{IP = $ip; HostName = $dnsTask.Result.HostName}
			} else {
				return [PSCustomObject]@{IP = $ip; HostName = "Unable to Resolve"}
			}
		}

		# Setup separate RunspacePool
		$iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
		$rsHost = [runspacefactory]::CreateRunspace($iss)
		$rsHost.Open()
		$rsPool = [runspacefactory]::CreateRunspacePool(1, 10, $rsHost, $RunspacePool.ApartmentState)
		$rsPool.Open()

		# Start hostNameJobs - responses first
		$hostNameJobs = @()
		foreach ($item in $pingItems) {
			if($item.Hostname -eq 'Resolving...'){
				$hostNameJob = [powershell]::Create().AddScript($resolveScript).AddArgument($item.IPaddress).AddArgument($timeout)
				$hostNameJob.RunspacePool = $rsPool
				$hostNameJobHandle = $hostNameJob.BeginInvoke()
				$hostNameJobs += [PSCustomObject]@{
					Pipeline = $hostNameJob
					Handle = $hostNameJobHandle
					IP = $item.IPaddress
				}
			}
		}
		foreach ($item in $nonPingItems) {
			if($item.Hostname -eq 'Resolving...'){
				$hostNameJob = [powershell]::Create().AddScript($resolveScript).AddArgument($item.IPaddress).AddArgument($timeout)
				$hostNameJob.RunspacePool = $rsPool
				$hostNameJobHandle = $hostNameJob.BeginInvoke()
				$hostNameJobs += [PSCustomObject]@{
					Pipeline = $hostNameJob
					Handle = $hostNameJobHandle
					IP = $item.IPaddress
				}
			}
		}

		# Process hostNameJobs
		while ($hostNameJobs.Count -gt 0) {
			for ($i = $hostNameJobs.Count - 1; $i -ge 0; $i--) {
				$hostNameJob = $hostNameJobs[$i]
				if ($hostNameJob.Handle.IsCompleted) {
					$result = $hostNameJob.Pipeline.EndInvoke($hostNameJob.Handle)
					foreach ($it in $listView.Items) {
						if ($it.IPaddress -eq $hostNameJob.IP) {
							$it.HostName = $result.HostName
							break
						}
					}
					$hostNameJob.Pipeline.Dispose()
					$hostNameJobs.RemoveAt($i)
				}
			}
			Start-Sleep -Milliseconds 10
		}

		# Cleanup
		$rsPool.Close()
		$rsPool.Dispose()
		$rsHost.Close()
		$rsHost.Dispose()

	}, $true).AddArgument($listView).AddArgument($internalIP).AddArgument($RunspacePool).AddArgument($global:gatewayPrefix).AddArgument($originalGatewayPrefix)
	$hostnameLookupThread.RunspacePool = $RunspacePool
	$hostnameScan = $hostnameLookupThread.BeginInvoke()
}

# Portscan
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
			return "Port`: $port is open"
		}
		else {
			return $null
		}
	}
	catch {
		return $null
	}
	finally {
		$tcp.Close()
	}
}

# Check common ports
function CheckConnectivity {
	param (
		[string]$selectedhost
	)
	# Disable all buttons for 'This Device'
	if ($selectedhost -match $internalIP) {
		@('btnRDP', 'btnWebInterface', 'btnShare') | ForEach-Object {
			Get-Variable $_ -ValueOnly | ForEach-Object {
				$_.IsEnabled = $false
				$_.Visibility = 'Collapsed'
			}
		}
		$btnNone.IsEnabled = $true
		$btnNone.Visibility = 'Visible'
		return
	}
	$global:tryToConnect = $selectedhost -replace ' (This Device)', ''

	# Find the item in ListView based on IP or HostName
	$selectedItem = $listView.Items | Where-Object {
		$_.IPaddress -eq $tryToConnect -or $_.HostName -eq $selectedhost
	} | Select-Object -First 1

	# Check connectivity for different protocols
	$ports = @{
		HTTP = 80
		HTTPS = 443
		SMBv2 = 445
		SMB = 139
		RDP = 3389
	}
	$results = @{}
	foreach ($protocol in $ports.Keys) {
		$results[$protocol] = Test-Port -computer $tryToConnect -port $ports[$protocol] -timeout 200
	}

	# Update button states based on connectivity results
	$btnShare.IsEnabled = ($results.SMBv2 -or $results.SMB) -and $HostName -ne $tryToConnect
	$btnShare.Visibility = if ($btnShare.IsEnabled) { 'Visible' } else { 'Collapsed' }

	if ($btnShare.Visibility -eq 'Visible') {$btnWebInterface.Margin = "0,0,25,0"} else {$btnWebInterface.Margin = "0,0,0,0"}
	$btnWebInterface.IsEnabled = ($results.HTTP -or $results.HTTPS) -and $HostName -ne $tryToConnect
	$btnWebInterface.Visibility = if ($btnWebInterface.IsEnabled) { 'Visible' } else { 'Collapsed' }
	$global:httpAvailable = if ($results.HTTP) { 1 } else { 0 }

	if ($btnShare.Visibility -eq 'Visible' -or $btnWebInterface.Visibility -eq 'Visible') {$btnRDP.Margin = "0,0,25,0"} else {$btnRDP.Margin = "0,0,0,0"}
	$btnRDP.IsEnabled = $results.RDP -and $HostName -ne $tryToConnect
	$btnRDP.Visibility = if ($btnRDP.IsEnabled) { 'Visible' } else { 'Collapsed' }

	# Show no connections icon if nothing is available
	if (-not $btnRDP.IsEnabled -and -not $btnWebInterface.IsEnabled -and -not $btnShare.IsEnabled) {
		$btnNone.IsEnabled = $true
		$btnNone.Visibility = 'Visible'
	} else {
		$btnNone.IsEnabled = $false
		$btnNone.Visibility = 'Collapsed'
	}

	# Show ping response status in popup window
	$pingStatusImage.Content = Create-GradientEllipse -isPingSuccessful $selectedItem.Ping -width 12 -height 12
	$pingStatusText.Text = if ($selectedItem.Ping) { "ICMP response received" } else { "No ICMP response received" }
}

# Listview column sort logic
$sortDirections = @{}
$listViewSortColumn = {
	param([System.Object]$sender, [System.EventArgs]$Event)
	$column = $Event.OriginalSource.Column

	# Determine current direction, toggle if column has been sorted before
	switch ($true) {
		{$sortDirections.ContainsKey($column.Header)} {
			$sortDirections[$column.Header] = -not $sortDirections[$column.Header]
		}
		default {
			# false for descending, true for ascending
			$sortDirections[$column.Header] = $false
		}
	}
	$direction = if ($sortDirections[$column.Header]) { "Ascending" } else { "Descending" }

	# Sort items
	$sortedItems = switch ($column.Header) {
		"IP Address" {
			$Sender.Items | Sort-Object -Property {[version]$_.IPaddress} -Descending:($direction -eq "Descending")
		}
		default {
			if ($column.DisplayMemberBinding.Path.Path) {
				$Sender.Items | Sort-Object -Property $column.DisplayMemberBinding.Path.Path -Descending:($direction -eq "Descending")
			} else {
				$Sender.Items
			}
		}
	}
	# Rebuild sorted list
	$Sender.Items.Clear()
	$sortedItems | ForEach-Object { $Sender.Items.Add($_) }
}

function Create-GradientEllipse {
	param (
		[bool]$isPingSuccessful,
		[double]$width = 9,
		[double]$height = 9
	)

	$ellipse = [Windows.Shapes.Ellipse]::new()
	$ellipse.Width = $width
	$ellipse.Height = $height

	if ($isPingSuccessful) {
		# Lighter blue gradient for successful ping
		$gradient = New-Object System.Windows.Media.RadialGradientBrush
		$gradient.GradientOrigin = New-Object System.Windows.Point(0.5, 0.5)
		$gradient.Center = New-Object System.Windows.Point(0.5, 0.5)
		$gradient.RadiusX = 0.5
		$gradient.RadiusY = 0.5
		$stop1 = New-Object System.Windows.Media.GradientStop
		$stop1.Color = [System.Windows.Media.Color]::FromArgb(255, 51, 204, 255)
		$stop1.Offset = 0
		$gradient.GradientStops.Add($stop1)
		$stop2 = New-Object System.Windows.Media.GradientStop
		$stop2.Color = [System.Windows.Media.Color]::FromArgb(255, 25, 153, 204)
		$stop2.Offset = 0.8
		$gradient.GradientStops.Add($stop2)
		$stop3 = New-Object System.Windows.Media.GradientStop
		$stop3.Color = [System.Windows.Media.Color]::FromArgb(255, 0, 102, 153)
		$stop3.Offset = 1
		$gradient.GradientStops.Add($stop3)
	} else {
		# Shades of gray for unsuccessful ping
		$gradient = New-Object System.Windows.Media.RadialGradientBrush
		$gradient.GradientOrigin = New-Object System.Windows.Point(0.5, 0.5)
		$gradient.Center = New-Object System.Windows.Point(0.5, 0.5)
		$gradient.RadiusX = 0.5
		$gradient.RadiusY = 0.5
		$stop4 = New-Object System.Windows.Media.GradientStop
		$stop4.Color = [System.Windows.Media.Color]::FromArgb(255, 220, 220, 220)
		$stop4.Offset = 0
		$gradient.GradientStops.Add($stop4)
		$stop5 = New-Object System.Windows.Media.GradientStop
		$stop5.Color = [System.Windows.Media.Color]::FromArgb(255, 160, 160, 160)
		$stop5.Offset = 0.8
		$gradient.GradientStops.Add($stop5)
		$stop6 = New-Object System.Windows.Media.GradientStop
		$stop6.Color = [System.Windows.Media.Color]::FromArgb(255, 100, 100, 100)
		$stop6.Offset = 1
		$gradient.GradientStops.Add($stop6)
	}

	$ellipse.Fill = $gradient
	return $ellipse
}

# Display network speed as KB/s -MB/s -GB/s
function Format-Speed {
	param ([double]$speedInKBs)
	if ($speedInKBs -ge 1024 * 1024) { return "{0:N1}gb" -f ($speedInKBs / (1024 * 1024)) }
	elseif ($speedInKBs -ge 1024) { return "{0:N1}mb" -f ($speedInKBs / 1024) }
	else { return "{0:N0}kb" -f $speedInKBs }
}

# Initialize hashtable for Monitor Mode
$global:syncHash = [Hashtable]::Synchronized(@{
	NetworkStats = @{}
	TCPConnections = @()
	LastUpdate = [DateTime]::Now
	Error = $null
})

function Start-NetMonBackgroundTask {
	$backgroundScript = {
		param($syncHash, $adapters)
		function Get-NetworkStatsWithTimeout {
			$statsPerAdapter = @{}
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			$timeoutMs = 100
			$retryCount = 2
			for ($i = 0; $i -lt $retryCount; $i++) {
				try {
					$currentAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Loopback*" -and $_.InterfaceDescription -notlike "*ISATAP*" }
					if (-not $currentAdapters) {
						return $statsPerAdapter
					}
					foreach ($adapter in $currentAdapters) {
						$adapterName = $adapter.Name
						$stats = Get-NetAdapterStatistics -Name $adapterName -ErrorAction SilentlyContinue
						if ($stats) {
							$statsPerAdapter[$adapterName] = @{
								RxBytes = [double]$stats.ReceivedBytes
								TxBytes = [double]$stats.SentBytes
								Timestamp = [double](Get-Date).Ticks
							}
						} else {
							$global:syncHash.Error =  "No stats returned for adapter: $adapterName"
						}
					}
					if ($statsPerAdapter.Count -gt 0) { break }
					Start-Sleep -Milliseconds 100
				} catch {
					$global:syncHash.Error = "Network stats error: $_"
				}
				$stopwatch.Stop()
				if ($stopwatch.ElapsedMilliseconds -gt $timeoutMs) { break }
				$stopwatch.Restart()
			}
			return $statsPerAdapter
		}
		function Get-TCPConnections {
			try {
				$connections = Get-NetTCPConnection | Where-Object { $_.State -eq "Established" }
				$tcpList = @()
				foreach ($conn in $connections) {
					$process = Get-CimInstance Win32_Process -Filter "ProcessId = $($conn.OwningProcess)" -ErrorAction SilentlyContinue
					$processName = if ($process) { $process.Name } else { "Unknown" }
					$tcpList += [PSCustomObject]@{
						LocalAddress = $conn.LocalAddress; LocalPort = $conn.LocalPort; RemoteAddress = $conn.RemoteAddress; RemotePort = $conn.RemotePort; ProcessName = $processName
					}
				}
				return $tcpList
			} catch {
				$global:syncHash.Error = "TCP connections error: $_"
				return @()
			}
		}
		while ($true) {
			try {
				$stats = Get-NetworkStatsWithTimeout
				$tcp = Get-TCPConnections
				$global:syncHash.NetworkStats = $stats
				$global:syncHash.TCPConnections = $tcp
				$global:syncHash.LastUpdate = [DateTime]::Now
				$global:syncHash.Error = $null
			} catch {
				Write-Host "Background task error: $_"
				$global:syncHash.Error = $_.ToString()
			}
			Start-Sleep -Milliseconds 1000
		}
	}
	$runspace = [PowerShell]::Create().AddScript($backgroundScript).AddArgument($syncHash).AddArgument($adapters)
	$runspace.RunspacePool = $RunspacePool
	return $runspace.BeginInvoke()
}

# Direct MAC request via iphlpapi.dll
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class MacAddressResolver
{
	[DllImport("iphlpapi.dll", ExactSpelling = true)]
	public static extern int SendARP(uint DestIP, uint SrcIP, byte[] pMacAddr, ref int PhyAddrLen);

	public static string GetMacFromIP(string ipAddress)
	{
		try
		{
			System.Net.IPAddress ip = System.Net.IPAddress.Parse(ipAddress);
			byte[] macAddr = new byte[6];
			int macAddrLen = macAddr.Length;
			if (SendARP(BitConverter.ToUInt32(ip.GetAddressBytes(), 0), 0, macAddr, ref macAddrLen) == 0)
			{
				string[] str = new string[macAddr.Length];
				for (int i = 0; i < macAddr.Length; i++)
				{
					str[i] = macAddr[i].ToString("X2");
				}
				return string.Join(":", str);
			}
			else
			{
				return "Unknown";
			}
		}
		catch
		{
			return "Unknown";
		}
	}
}
"@

# Get icons from DLL or EXE files via shell32.dll
$getIcons = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows;

namespace System
{
	public class IconExtractor
	{
		public static Icon Extract(string file, int number, bool largeIcon)
		{
			IntPtr large;
			IntPtr small;
			ExtractIconEx(file, number, out large, out small, 1);
			try
			{
				return Icon.FromHandle(largeIcon ? large : small);
			}
			catch
			{
				return null;
			}
		}
		public static BitmapSource IconToBitmapSource(Icon icon)
		{
			return Imaging.CreateBitmapSourceFromHIcon(
				icon.Handle,
				Int32Rect.Empty,
				BitmapSizeOptions.FromEmptyOptions());
		}
		[DllImport("Shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
		private static extern int ExtractIconEx(string sFile, int iIndex, out IntPtr piLargeVersion, out IntPtr piSmallVersion, int amountIcons);
	}
}
"@

# Define WPF GUI Structure
Add-Type -TypeDefinition $getIcons -ReferencedAssemblies System.Windows.Forms, System.Drawing, PresentationCore, PresentationFramework, WindowsBase
[xml]$XAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Height="500" Width="900" Background="Transparent" AllowsTransparency="True" WindowStyle="None">
	<Window.Resources>
		<ControlTemplate x:Key="NoMouseOverButtonTemplate" TargetType="Button">
			<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
				<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
			</Border>
			<ControlTemplate.Triggers>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Background" Value="{x:Static SystemColors.ControlLightBrush}"/>
					<Setter Property="Foreground" Value="{x:Static SystemColors.GrayTextBrush}"/>
				</Trigger>
			</ControlTemplate.Triggers>
		</ControlTemplate>
		<ControlTemplate x:Key="CloseButtonTemplate" TargetType="Button">
			<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="0,5,0,0">
				<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
			</Border>
			<ControlTemplate.Triggers>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Background" Value="{x:Static SystemColors.ControlLightBrush}"/>
					<Setter Property="Foreground" Value="{x:Static SystemColors.GrayTextBrush}"/>
				</Trigger>
			</ControlTemplate.Triggers>
		</ControlTemplate>
		<ControlTemplate x:Key="NoMouseOverColumnHeaderTemplate" TargetType="{x:Type GridViewColumnHeader}">
			<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
				<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True"/>
			</Border>
			<ControlTemplate.Triggers>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Background" Value="{x:Static SystemColors.ControlLightBrush}"/>
					<Setter Property="Foreground" Value="{x:Static SystemColors.GrayTextBrush}"/>
				</Trigger>
			</ControlTemplate.Triggers>
		</ControlTemplate>
		<Style x:Key="ScrollThumbs" TargetType="{x:Type Thumb}">
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type Thumb}">
						<Grid x:Name="Grid">
							<Rectangle HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto" Fill="Transparent"/>
							<Border x:Name="Rectangle1" CornerRadius="5" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto" Background="{TemplateBinding Background}"/>
						</Grid>
						<ControlTemplate.Triggers>
							<Trigger Property="Tag" Value="Horizontal">
								<Setter TargetName="Rectangle1" Property="Width" Value="Auto"/>
								<Setter TargetName="Rectangle1" Property="Height" Value="7"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="{x:Type ScrollBar}" TargetType="{x:Type ScrollBar}">
			<Setter Property="Stylus.IsPressAndHoldEnabled" Value="True"/>
			<Setter Property="Stylus.IsFlicksEnabled" Value="True" />
			<Setter Property="Background" Value="#333333"/>
			<Setter Property="BorderThickness" Value="1,0"/>
			<Setter Property="BorderBrush" Value="#000000"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ScrollBar}">
						<Grid x:Name="GridRoot" Width="{TemplateBinding Width}" Height="{TemplateBinding Height}" SnapsToDevicePixels="True">
							<Track x:Name="PART_Track" IsDirectionReversed="true" Focusable="false">
								<Track.Thumb>
									<Thumb x:Name="Thumb" Style="{StaticResource ScrollThumbs}" Background="#777777" />
								</Track.Thumb>
							</Track>
						</Grid>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
			<Style.Triggers>
				<Trigger Property="Orientation" Value="Vertical">
					<Setter Property="Width" Value="10" />
					<Setter Property="Height" Value="396" />
					<Setter Property="MinHeight" Value="396" />
					<Setter Property="MinWidth" Value="10" />
				</Trigger>
				<Trigger Property="Orientation" Value="Horizontal">
					<Setter Property="Width" Value="845" />
					<Setter Property="Height" Value="10" />
					<Setter Property="MinHeight" Value="10" />
					<Setter Property="MinWidth" Value="845" />
					<Setter Property="Margin" Value="-2,0,0,0" />
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style x:Key="ColumnHeaderStyle" TargetType="{x:Type GridViewColumnHeader}">
			<Setter Property="Template" Value="{StaticResource NoMouseOverColumnHeaderTemplate}" />
			<Setter Property="Background" Value="#CCCCCC" />
			<Setter Property="Foreground" Value="Black" />
			<Setter Property="BorderBrush" Value="#333333" />
			<Setter Property="BorderThickness" Value="0,0,2,0" />
			<Setter Property="Cursor" Value="Arrow" />
			<Setter Property="FontWeight" Value="Bold"/>
			<Style.Triggers>
				<Trigger Property="IsMouseOver" Value="True">
					<Setter Property="Background" Value="#EEEEEE" />
					<Setter Property="Foreground" Value="Black" />
					<Setter Property="BorderBrush" Value="#333333" />
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style x:Key="CustomContextMenuStyle" TargetType="{x:Type ContextMenu}">
			<Setter Property="Background" Value="#666666"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="BorderBrush" Value="#333333"/>
			<Setter Property="BorderThickness" Value="0,0,2,0"/>
			<Setter Property="OverridesDefaultStyle" Value="True"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ContextMenu}">
						<Border CornerRadius="2,4,4,2" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
							<StackPanel>
								<ItemsPresenter/>
							</StackPanel>
						</Border>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="CustomMenuItemStyle" TargetType="{x:Type MenuItem}">
			<Setter Property="Background" Value="#666666"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type MenuItem}">
						<Border x:Name="Border" BorderThickness="0.70" CornerRadius="2,4,4,4" Background="Transparent" SnapsToDevicePixels="True" Padding="12,3,12,3">
							<Grid>
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="Auto"/>
									<ColumnDefinition Width="Auto"/>
								</Grid.ColumnDefinitions>
								<ContentPresenter Margin="1" ContentSource="Header" RecognizesAccessKey="True" Grid.Column="0"/>
								<Popup x:Name="PART_Popup" Placement="Right" VerticalOffset="-5" HorizontalOffset="5" AllowsTransparency="True" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}" PopupAnimation="Fade">
									<Border x:Name="SubMenuBorder" CornerRadius="2,4,4,4" SnapsToDevicePixels="True" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="0.70">
										<StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
									</Border>
								</Popup>
							</Grid>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsHighlighted" Value="true">
								<Setter Property="Background" TargetName="Border" Value="#4000B7FF"/>
								<Setter Property="BorderBrush" TargetName="Border" Value="#FF00BFFF"/>
							</Trigger>
							<Trigger Property="IsEnabled" Value="False">
								<Setter Property="Foreground" Value="#888888"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="MainMenuItemStyle" TargetType="{x:Type MenuItem}">
			<Setter Property="Background" Value="#666666"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type MenuItem}">
						<Border x:Name="Border" BorderThickness="0.70" CornerRadius="2,4,4,4" Background="Transparent" SnapsToDevicePixels="True" Padding="12,3,12,3">
							<Grid>
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="Auto"/>
									<ColumnDefinition Width="Auto"/>
								</Grid.ColumnDefinitions>
								<ContentPresenter Margin="1" ContentSource="Header" RecognizesAccessKey="True" Grid.Column="0"/>
								<Path x:Name="BlackArrow" Data="M0 0 L5 2.5 L0 5 Z" Width="5" Height="5" Margin="7,2,0,0" Grid.Column="1">
									<Path.Fill>
										<SolidColorBrush Color="#EEEEEE"/>
									</Path.Fill>
								</Path>
								<Path x:Name="GrayArrow" Data="M0 0 L5 2.5 L0 5 Z" Width="5" Height="5" Margin="7,2,0,0" Grid.Column="1">
									<Path.Fill>
										<SolidColorBrush Color="#888888"/>
									</Path.Fill>
								</Path>
								<Popup x:Name="PART_Popup" Placement="Right" VerticalOffset="-5" HorizontalOffset="5" AllowsTransparency="True" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}" PopupAnimation="Fade">
									<Border x:Name="SubMenuBorder" CornerRadius="2,4,4,4" SnapsToDevicePixels="True" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="0.70">
										<StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
									</Border>
								</Popup>
							</Grid>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsHighlighted" Value="true">
								<Setter Property="Background" TargetName="Border" Value="#555555"/>
								<Setter Property="BorderBrush" TargetName="Border" Value="#FF00BFFF"/>
							</Trigger>
							<Trigger Property="IsEnabled" Value="False">
								<Setter Property="Foreground" Value="#888888"/>
								<Setter TargetName="BlackArrow" Property="Visibility" Value="Collapsed"/>
								<Setter TargetName="GrayArrow" Property="Visibility" Value="Visible"/>
							</Trigger>
							<Trigger Property="IsEnabled" Value="True">
								<Setter TargetName="BlackArrow" Property="Visibility" Value="Visible"/>
								<Setter TargetName="GrayArrow" Property="Visibility" Value="Collapsed"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="CustomComboBoxStyle" TargetType="{x:Type ComboBox}">
			<Setter Property="Width" Value="50"/>
			<Setter Property="Height" Value="25"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="Margin" Value="0,0,5,0"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ComboBox}">
						<Grid>
							<ToggleButton Name="ToggleButton" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" Background="#333333" Foreground="#EEEEEE" BorderThickness="0.85" BorderBrush="#FF00BFFF">
								<TextBlock Text="{Binding SelectedItem, RelativeSource={RelativeSource TemplatedParent}}" HorizontalAlignment="Left" VerticalAlignment="Center" Foreground="#EEEEEE" Margin="5,0,0,0"/>
								<ToggleButton.Template>
									<ControlTemplate TargetType="{x:Type ToggleButton}">
										<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
											<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
										</Border>
										<ControlTemplate.Triggers>
											<Trigger Property="IsMouseOver" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
											<Trigger Property="IsChecked" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
										</ControlTemplate.Triggers>
									</ControlTemplate>
								</ToggleButton.Template>
							</ToggleButton>
							<Popup IsOpen="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide" Width="50">
								<Border Name="DropDownBorder" BorderBrush="#CCCCCC" BorderThickness="0.80" Background="#444444">
									<ScrollViewer MaxHeight="150" VerticalScrollBarVisibility="Hidden">
										<StackPanel IsItemsHost="True">
											<StackPanel.Resources>
												<Style TargetType="{x:Type ComboBoxItem}">
													<Setter Property="Foreground" Value="#EEEEEE"/>
													<Setter Property="Background" Value="#444444"/>
													<Setter Property="HorizontalContentAlignment" Value="Center"/>
													<Style.Triggers>
														<Trigger Property="IsHighlighted" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
														<Trigger Property="IsSelected" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
													</Style.Triggers>
												</Style>
											</StackPanel.Resources>
										</StackPanel>
									</ScrollViewer>
								</Border>
							</Popup>
						</Grid>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
							<Trigger Property="IsDropDownOpen" Value="True">
								<Setter TargetName="DropDownBorder" Property="BorderBrush" Value="#FF00BFFF"/>
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="CustomComboBoxStyle2" TargetType="{x:Type ComboBox}">
			<Setter Property="Width" Value="98"/>
			<Setter Property="Height" Value="25"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="Margin" Value="0,0,5,0"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ComboBox}">
						<Grid>
							<ToggleButton Name="ToggleButton" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" Background="#333333" Foreground="#EEEEEE" BorderThickness="0.85" BorderBrush="#FF00BFFF">
								<TextBlock Text="{Binding SelectedItem, RelativeSource={RelativeSource TemplatedParent}}" HorizontalAlignment="Left" VerticalAlignment="Center" Foreground="#EEEEEE" Margin="5,0,0,0"/>
								<ToggleButton.Template>
									<ControlTemplate TargetType="{x:Type ToggleButton}">
										<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
											<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
										</Border>
										<ControlTemplate.Triggers>
											<Trigger Property="IsMouseOver" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
											<Trigger Property="IsChecked" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
										</ControlTemplate.Triggers>
									</ControlTemplate>
								</ToggleButton.Template>
							</ToggleButton>
							<Popup IsOpen="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide" Width="98">
								<Border Name="DropDownBorder" BorderBrush="#CCCCCC" BorderThickness="0.80" Background="#444444">
									<ScrollViewer MaxHeight="135" VerticalScrollBarVisibility="Hidden">
										<StackPanel IsItemsHost="True">
											<StackPanel.Resources>
												<Style TargetType="{x:Type ComboBoxItem}">
													<Setter Property="Foreground" Value="#EEEEEE"/>
													<Setter Property="Background" Value="#444444"/>
													<Setter Property="HorizontalContentAlignment" Value="Center"/>
													<Style.Triggers>
														<Trigger Property="IsHighlighted" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
														<Trigger Property="IsSelected" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
													</Style.Triggers>
												</Style>
											</StackPanel.Resources>
										</StackPanel>
									</ScrollViewer>
								</Border>
							</Popup>
						</Grid>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
							<Trigger Property="IsDropDownOpen" Value="True">
								<Setter TargetName="DropDownBorder" Property="BorderBrush" Value="#FF00BFFF"/>
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="NetMonComboBoxStyle" TargetType="{x:Type ComboBox}">
			<Setter Property="Width" Value="150"/>
			<Setter Property="Height" Value="25"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="Margin" Value="0,0,5,0"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ComboBox}">
						<Grid>
							<ToggleButton Name="ToggleButton" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" Background="#333333" Foreground="#EEEEEE" BorderThickness="0.85" BorderBrush="#FF00BFFF">
								<ToggleButton.Template>
									<ControlTemplate TargetType="{x:Type ToggleButton}">
										<Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
											<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
										</Border>
										<ControlTemplate.Triggers>
											<Trigger Property="IsMouseOver" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
											<Trigger Property="IsChecked" Value="True">
												<Setter Property="BorderBrush" Value="#FF00BFFF"/>
											</Trigger>
										</ControlTemplate.Triggers>
									</ControlTemplate>
								</ToggleButton.Template>
								<DockPanel LastChildFill="False">
									<TextBlock Text="{Binding SelectedItem, RelativeSource={RelativeSource TemplatedParent}}" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="#EEEEEE" Margin="5,0,5,0"/>
									<Path x:Name="ComboArrow" DockPanel.Dock="Right" Data="M0 0 L5 2.5 L10 0 Z" Width="10" Height="5" Margin="5,0,5,0" Stretch="Fill" VerticalAlignment="Center">
										<Path.Fill><SolidColorBrush Color="#EEEEEE"/></Path.Fill>
									</Path>
								</DockPanel>
							</ToggleButton>
							<Popup IsOpen="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide" Width="150">
								<Border Name="DropDownBorder" BorderBrush="#CCCCCC" BorderThickness="0.80" Background="#444444">
									<ScrollViewer MaxHeight="150" VerticalScrollBarVisibility="Auto">
										<StackPanel IsItemsHost="True">
											<StackPanel.Resources>
												<Style TargetType="{x:Type ComboBoxItem}">
													<Setter Property="Foreground" Value="#EEEEEE"/>
													<Setter Property="Background" Value="#444444"/>
													<Setter Property="HorizontalContentAlignment" Value="Left"/>
													<Style.Triggers>
														<Trigger Property="IsHighlighted" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
														<Trigger Property="IsSelected" Value="True">
															<Setter Property="Background" Value="#555555"/>
														</Trigger>
													</Style.Triggers>
												</Style>
											</StackPanel.Resources>
										</StackPanel>
									</ScrollViewer>
								</Border>
							</Popup>
						</Grid>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
							<Trigger Property="IsDropDownOpen" Value="True">
								<Setter TargetName="DropDownBorder" Property="BorderBrush" Value="#FF00BFFF"/>
								<Setter TargetName="ToggleButton" Property="BorderBrush" Value="#EEEEEE"/>
							</Trigger>
							<Trigger Property="IsEnabled" Value="False">
								<Setter TargetName="ComboArrow" Property="Fill" Value="#888888"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="NetMonListViewStyle" TargetType="{x:Type ListView}">
			<Setter Property="Background" Value="#333333"/>
			<Setter Property="Foreground" Value="#EEEEEE"/>
			<Setter Property="FontWeight" Value="Normal"/>
			<Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
			<Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Hidden"/>
			<Setter Property="ScrollViewer.CanContentScroll" Value="False"/>
			<Setter Property="AlternationCount" Value="2"/>
			<Setter Property="ItemContainerStyle">
				<Setter.Value>
					<Style TargetType="{x:Type ListViewItem}">
						<Setter Property="Background" Value="Transparent"/>
						<Setter Property="Foreground" Value="#EEEEEE"/>
						<Setter Property="BorderBrush" Value="Transparent"/>
						<Setter Property="BorderThickness" Value="0.70"/>
						<Setter Property="Template">
							<Setter.Value>
								<ControlTemplate TargetType="{x:Type ListViewItem}">
									<Border BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Background="{TemplateBinding Background}">
										<GridViewRowPresenter HorizontalAlignment="Stretch" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Width="Auto" Margin="0" Content="{TemplateBinding Content}"/>
									</Border>
									<ControlTemplate.Triggers>
										<Trigger Property="ItemsControl.AlternationIndex" Value="0">
											<Setter Property="Background" Value="#111111"/>
										</Trigger>
										<Trigger Property="ItemsControl.AlternationIndex" Value="1">
											<Setter Property="Background" Value="#000000"/>
										</Trigger>
										<Trigger Property="IsMouseOver" Value="True">
											<Setter Property="Background" Value="#4000B7FF"/>
											<Setter Property="BorderBrush" Value="#FF00BFFF"/>
										</Trigger>
										<MultiTrigger>
											<MultiTrigger.Conditions>
												<Condition Property="IsSelected" Value="true"/>
												<Condition Property="Selector.IsSelectionActive" Value="true"/>
											</MultiTrigger.Conditions>
											<Setter Property="Background" Value="#4000B7FF"/>
											<Setter Property="FontWeight" Value="Bold"/>
											<Setter Property="BorderBrush" Value="#FF00BFFF"/>
										</MultiTrigger>
									</ControlTemplate.Triggers>
								</ControlTemplate>
							</Setter.Value>
						</Setter>
					</Style>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="NetMonColumnHeaderStyle" TargetType="{x:Type GridViewColumnHeader}">
			<Setter Property="Template" Value="{StaticResource NoMouseOverColumnHeaderTemplate}" />
			<Setter Property="Background" Value="#CCCCCC" />
			<Setter Property="Foreground" Value="Black" />
			<Setter Property="BorderBrush" Value="#333333" />
			<Setter Property="BorderThickness" Value="0,0,2,0" />
			<Setter Property="Cursor" Value="Arrow" />
			<Setter Property="FontWeight" Value="Bold"/>
			<Setter Property="IsHitTestVisible" Value="False" />
			<Style.Triggers>
				<Trigger Property="IsMouseOver" Value="True">
					<Setter Property="Background" Value="#CCCCCC" />
					<Setter Property="Foreground" Value="Black" />
					<Setter Property="BorderBrush" Value="#333333" />
				</Trigger>
			</Style.Triggers>
		</Style>
		<ContextMenu x:Key="NetMonRightClickContextMenu" Style="{StaticResource CustomContextMenuStyle}">
			<MenuItem Header="    Export    " Name="NetMonExportContext" Style="{StaticResource MainMenuItemStyle}">
				<MenuItem Header="   HTML   " Name="NetMonExportToHTML" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   CSV    " Name="NetMonExportToCSV" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   Text   " Name="NetMonExportToText" Style="{StaticResource CustomMenuItemStyle}"/>
			</MenuItem>
		</ContextMenu>
		<ContextMenu x:Key="NetMonDoubleClickContextMenu" Style="{StaticResource CustomContextMenuStyle}">
			<MenuItem Header="    Copy    " Style="{StaticResource MainMenuItemStyle}">
				<MenuItem Header="   Local Address  " Name="CopyLocalAddress" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   Local Port     " Name="CopyLocalPort" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   Remote Address " Name="CopyRemoteAddress" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   Remote Port    " Name="CopyRemotePort" Style="{StaticResource CustomMenuItemStyle}"/>
				<MenuItem Header="   Process Name   " Name="CopyProcessName" Style="{StaticResource CustomMenuItemStyle}"/>
				<Separator Background="#222222"/>
				<MenuItem Header="   All            " Name="CopyAll" Style="{StaticResource CustomMenuItemStyle}"/>
			</MenuItem>
		</ContextMenu>
	</Window.Resources>
	<Border Background="#222222" CornerRadius="5,5,5,5">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="30"/>
				<RowDefinition Height="*"/>
			</Grid.RowDefinitions>
			<Border Background="#DDDDDD" Grid.Row="0" CornerRadius="5,5,0,0">
				<Grid>
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<Image Name="WindowIconImage" Width="24" Height="24" VerticalAlignment="Center" Margin="8,0,8,0">
						<Image.Effect>
							<DropShadowEffect BlurRadius="5" ShadowDepth="1" Opacity="0.8" Direction="270" Color="Black"/>
						</Image.Effect>
					</Image>
					<TextBlock Name="TitleBar" Foreground="Black" FontWeight="Bold" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="0,0,5,0" Grid.Column="1"/>
					<Grid Grid.Column="2">
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="Auto"/>
							<ColumnDefinition Width="Auto"/>
						</Grid.ColumnDefinitions>
						<TextBlock Name="externalIPt" Foreground="Black" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,5,0"/>
						<TextBlock Name="domainName" Foreground="Black" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,5,0" Grid.Column="1"/>
					</Grid>
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Grid.Column="3">
						<Button Name="ToggleMonitorButton" Background="Transparent" BorderThickness="0" ToolTip="Monitor Mode" Template="{StaticResource NoMouseOverButtonTemplate}">
							<Button.Effect>
								<DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.7" Direction="270" Color="Black"/>
							</Button.Effect>
							<Button.Resources>
								<Storyboard x:Key="mouseEnterAnimation">
									<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-1" Duration="0:0:0.2"/>
									<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="3" Duration="0:0:0.2"/>
									<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="3" Duration="0:0:0.2"/>
								</Storyboard>
								<Storyboard x:Key="mouseLeaveAnimation">
									<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
									<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="1" Duration="0:0:0.2"/>
									<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="4" Duration="0:0:0.2"/>
								</Storyboard>
							</Button.Resources>
							<Button.RenderTransform>
								<TranslateTransform/>
							</Button.RenderTransform>
							<Viewbox Width="35" Height="24">
								<Canvas Width="35" Height="24">
									<Canvas Name="HideGraphic" Width="35" Height="24" Visibility="Hidden" IsHitTestVisible="False">
										<Path Canvas.Left="0" Canvas.Top="0">
											<Path.Fill>
												<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
													<GradientStop Color="#FF66D9FF" Offset="0"/>
													<GradientStop Color="#FF00BFFF" Offset="0.5"/>
													<GradientStop Color="#FF0077CC" Offset="1"/>
												</LinearGradientBrush>
											</Path.Fill>
											<Path.Data>
												M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5A6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z
											</Path.Data>
										</Path>
									</Canvas>
									<Canvas Name="ShowGraphic" Width="35" Height="24" Visibility="Visible" IsHitTestVisible="False">
										<Path Canvas.Left="0" Canvas.Top="0">
											<Path.Fill>
												<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
													<GradientStop Color="#FFCC66CC" Offset="0"/>
													<GradientStop Color="#FF800080" Offset="0.5"/>
													<GradientStop Color="#FF400040" Offset="1"/>
												</LinearGradientBrush>
											</Path.Fill>
											<Path.Data>
												M3,13H5.79L10.1,4.79L11.28,13.75L14.5,9.66L17.83,13H21V15H17L14.67,12.67L9.92,18.73L8.94,11.31L7,15H3V13Z
											</Path.Data>
										</Path>
									</Canvas>
								</Canvas>
							</Viewbox>
						</Button>
						<Button Name="btnMinimize" Width="40" Height="30" Background="Transparent" Foreground="Black" BorderThickness="0" Template="{StaticResource NoMouseOverButtonTemplate}">
							<Path Width="15" Height="2" Stretch="Fill" Stroke="Black" StrokeThickness="1" Data="M0,0 L15,0" HorizontalAlignment="Center" VerticalAlignment="Center"/>
						</Button>
						<Button Name="btnClose" Content="X" Width="40" Height="30" Background="Transparent" Foreground="Black" FontWeight="Bold" BorderThickness="0" Template="{StaticResource CloseButtonTemplate}"/>
					</StackPanel>
				</Grid>
			</Border>
			<Grid Grid.Row="1">
				<Grid Name="IPScannerContentGrid" Margin="0,0,50,0">
					<Grid Name="ScanContainer" Grid.Column="0" VerticalAlignment="Top" HorizontalAlignment="Center" Width="777" MinHeight="25" Margin="53,11,0,0">
						<Button Name="Scan" Width="777" Height="30" Background="#777777" Foreground="#000000" FontWeight="Bold" Template="{StaticResource NoMouseOverButtonTemplate}">
							<Button.ContextMenu>
								<ContextMenu Style="{StaticResource CustomContextMenuStyle}">
									<MenuItem Header="Subnet" Style="{StaticResource MainMenuItemStyle}" Name="ChangeSubnet"/>
								</ContextMenu>
							</Button.ContextMenu>
							<Button.Content>
								<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
									<TextBlock Name="ScanButtonText" Text="Scan" Foreground="#000000" FontWeight="Bold" />
									<Image Name="scanAdminIcon" Width="16" Height="16" Margin="5,0,0,0" Visibility="Collapsed"/>
								</StackPanel>
							</Button.Content>
							<Button.BorderBrush>
								<SolidColorBrush x:Name="CycleBrush" Color="White"/>
							</Button.BorderBrush>
						</Button>
						<ProgressBar Name="Progress" Foreground="#FF00BFFF" Background="#777777" Value="0" Maximum="100" Width="777" Height="30" Visibility="Collapsed"/>
						<TextBlock Name="BarText" Foreground="#000000" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
					</Grid>
					<ListView Name="listView" Background="#333333" FontWeight="Normal" HorizontalAlignment="Left" Height="400" Margin="19,52,-140,0" VerticalAlignment="Top" Width="860" VerticalContentAlignment="Top" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Hidden" ScrollViewer.CanContentScroll="False" AlternationCount="2">
						<ListView.ItemContainerStyle>
							<Style TargetType="{x:Type ListViewItem}">
								<Setter Property="Background" Value="Transparent" />
								<Setter Property="Foreground" Value="#EEEEEE"/>
								<Setter Property="BorderBrush" Value="Transparent"/>
								<Setter Property="BorderThickness" Value="0.70"/>
								<Setter Property="Template">
									<Setter.Value>
										<ControlTemplate TargetType="{x:Type ListViewItem}">
											<Border BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Background="{TemplateBinding Background}">
												<GridViewRowPresenter HorizontalAlignment="Stretch" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Width="Auto" Margin="0" Content="{TemplateBinding Content}"/>
											</Border>
											<ControlTemplate.Triggers>
												<Trigger Property="ItemsControl.AlternationIndex" Value="0">
													<Setter Property="Background" Value="#111111"/>
													<Setter Property="Foreground" Value="#EEEEEE"/>
												</Trigger>
												<Trigger Property="ItemsControl.AlternationIndex" Value="1">
													<Setter Property="Background" Value="#000000"/>
													<Setter Property="Foreground" Value="#EEEEEE"/>
												</Trigger>
												<Trigger Property="IsMouseOver" Value="True">
													<Setter Property="Background" Value="#4000B7FF"/>
													<Setter Property="Foreground" Value="#EEEEEE"/>
													<Setter Property="BorderBrush" Value="#FF00BFFF"/>
												</Trigger>
												<MultiTrigger>
													<MultiTrigger.Conditions>
														<Condition Property="IsSelected" Value="true"/>
														<Condition Property="Selector.IsSelectionActive" Value="true"/>
													</MultiTrigger.Conditions>
													<Setter Property="Background" Value="#4000B7FF"/>
													<Setter Property="Foreground" Value="#EEEEEE"/>
													<Setter Property="FontWeight" Value="Bold"/>
													<Setter Property="BorderBrush" Value="#FF00BFFF"/>
												</MultiTrigger>
											</ControlTemplate.Triggers>
										</ControlTemplate>
									</Setter.Value>
								</Setter>
							</Style>
						</ListView.ItemContainerStyle>
						<ListView.View>
							<GridView>
								<GridViewColumn Header="MAC Address" DisplayMemberBinding="{Binding MACaddress}" Width="150" HeaderContainerStyle="{StaticResource ColumnHeaderStyle}" />
								<GridViewColumn Header="Vendor" DisplayMemberBinding="{Binding Vendor}" Width="230" HeaderContainerStyle="{StaticResource ColumnHeaderStyle}" />
								<GridViewColumn Header="IP Address" Width="190" HeaderContainerStyle="{StaticResource ColumnHeaderStyle}">
									<GridViewColumn.CellTemplate>
										<DataTemplate>
											<StackPanel Orientation="Horizontal">
												<ContentControl Content="{Binding PingImage}" Width="16" Height="16" Margin="0,0,10,0"/>
												<TextBlock Text="{Binding IPaddress}"/>
											</StackPanel>
										</DataTemplate>
									</GridViewColumn.CellTemplate>
								</GridViewColumn>
								<GridViewColumn Header="Host Name" DisplayMemberBinding="{Binding HostName}" Width="284" HeaderContainerStyle="{StaticResource ColumnHeaderStyle}" />
							</GridView>
						</ListView.View>
						<ListView.ContextMenu>
							<ContextMenu Style="{StaticResource CustomContextMenuStyle}">
								<MenuItem Header="    Export    " Name="ExportContext" Style="{StaticResource MainMenuItemStyle}">
									<MenuItem Header="   HTML   " Name="ExportToHTML" Style="{StaticResource CustomMenuItemStyle}"/>
									<MenuItem Header="   CSV    " Name="ExportToCSV" Style="{StaticResource CustomMenuItemStyle}"/>
									<MenuItem Header="   Text   " Name="ExportToText" Style="{StaticResource CustomMenuItemStyle}"/>
								</MenuItem>
							</ContextMenu>
						</ListView.ContextMenu>
					</ListView>
					<TextBlock Name="TotalListed" Foreground="{x:Static SystemColors.GrayTextBrush}" FontWeight="Normal" FontSize="11" Margin="55,453,0,0" HorizontalAlignment="Center"/>
					<Canvas Name="PopupCanvas" Background="#222222" Visibility="Hidden" Width="350" Height="240" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="53,40,0,0">
						<Border Name="PopupBorder" CornerRadius="5" Width="350" Height="240" BorderThickness="0.70">
							<Border.BorderBrush>
								<SolidColorBrush Color="#CCCCCC"/>
							</Border.BorderBrush>
							<Grid Background="Transparent">
								<Grid.RowDefinitions>
									<RowDefinition Height="Auto"/>
									<RowDefinition Height="*"/>
								</Grid.RowDefinitions>
								<StackPanel Margin="10" Grid.Row="0">
									<StackPanel Orientation="Horizontal">
										<ContentControl Name="pingStatusImage" Width="12" Height="12" Margin="15,10,10,0"/>
										<TextBlock Name="pingStatusText" FontSize="14" Foreground="#EEEEEE" FontWeight="Bold" VerticalAlignment="Center" Margin="0,8,0,0"/>
									</StackPanel>
								</StackPanel>
								<StackPanel Margin="10" Grid.Row="1">
									<TextBlock Name="pHost" FontSize="14" Foreground="#EEEEEE" FontWeight="Bold" Margin="15,0,0,0"/>
									<StackPanel Orientation="Horizontal">
										<TextBlock Name="pIP" FontSize="14" Foreground="#EEEEEE" Margin="15,2,5,2" />
										<Button Name="btnPortScan" Width="13" Height="13" ToolTip="Scan Ports" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="True" Background="Transparent" Template="{StaticResource NoMouseOverButtonTemplate}">
											<Button.Effect>
												<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
											</Button.Effect>
											<Button.Resources>
												<Storyboard x:Key="mouseEnterAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-1" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="3" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="3" Duration="0:0:0.2"/>
												</Storyboard>
												<Storyboard x:Key="mouseLeaveAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="1.5" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="1.5" Duration="0:0:0.2"/>
												</Storyboard>
											</Button.Resources>
											<Button.RenderTransform>
												<TranslateTransform/>
											</Button.RenderTransform>
											<Viewbox Width="13" Height="13">
												<Path>
													<Path.Fill>
														<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
															<GradientStop Color="#FF66D9FF" Offset="0"/>
															<GradientStop Color="#FF00BFFF" Offset="0.5"/>
															<GradientStop Color="#FF0077CC" Offset="1"/>
														</LinearGradientBrush>
													</Path.Fill>
													<Path.Data>
														M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5A6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z
													</Path.Data>
												</Path>
											</Viewbox>
										</Button>
									</StackPanel>
									<TextBlock Name="pMAC" FontSize="14" Foreground="#EEEEEE" Margin="15,0,0,0" />
									<TextBlock Name="pVendor" FontSize="14" Foreground="#EEEEEE" Margin="15,0,0,0" />
									<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,28,0,0">
										<Button Name="btnRDP" Width="40" Height="32" ToolTip="Connect via RDP" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="False" Background="Transparent" Margin="0,0,25,0" Template="{StaticResource NoMouseOverButtonTemplate}">
											<Button.Effect>
												<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
											</Button.Effect>
											<Button.Resources>
												<Storyboard x:Key="mouseEnterAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-3" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="10" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="10" Duration="0:0:0.2"/>
												</Storyboard>
												<Storyboard x:Key="mouseLeaveAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="5" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="5" Duration="0:0:0.2"/>
												</Storyboard>
											</Button.Resources>
											<Button.RenderTransform>
												<TranslateTransform/>
											</Button.RenderTransform>
										</Button>
										<Button Name="btnWebInterface" Width="40" Height="32" ToolTip="Connect via Web Interface" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="False" Background="Transparent" Margin="0,0,25,0" Template="{StaticResource NoMouseOverButtonTemplate}">
											<Button.Effect>
												<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
											</Button.Effect>
											<Button.Resources>
												<Storyboard x:Key="mouseEnterAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-3" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="10" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="10" Duration="0:0:0.2"/>
												</Storyboard>
												<Storyboard x:Key="mouseLeaveAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="5" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="5" Duration="0:0:0.2"/>
												</Storyboard>
											</Button.Resources>
											<Button.RenderTransform>
												<TranslateTransform/>
											</Button.RenderTransform>
										</Button>
										<Button Name="btnShare" Width="40" Height="32" ToolTip="Connect via Share" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="False" Background="Transparent" Template="{StaticResource NoMouseOverButtonTemplate}">
											<Button.Effect>
												<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
											</Button.Effect>
											<Button.Resources>
												<Storyboard x:Key="mouseEnterAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-3" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="10" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="10" Duration="0:0:0.2"/>
												</Storyboard>
												<Storyboard x:Key="mouseLeaveAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="5" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="5" Duration="0:0:0.2"/>
												</Storyboard>
											</Button.Resources>
											<Button.RenderTransform>
												<TranslateTransform/>
											</Button.RenderTransform>
										</Button>
										<Button Name="btnNone" Width="40" Height="32" ToolTip="No Connections Found" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="False" Background="Transparent" Template="{StaticResource NoMouseOverButtonTemplate}">
											<Button.Effect>
												<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
											</Button.Effect>
											<Button.Resources>
												<Storyboard x:Key="mouseEnterAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-3" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="10" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="10" Duration="0:0:0.2"/>
												</Storyboard>
												<Storyboard x:Key="mouseLeaveAnimation">
													<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="5" Duration="0:0:0.2"/>
													<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="5" Duration="0:0:0.2"/>
												</Storyboard>
											</Button.Resources>
											<Button.RenderTransform>
												<TranslateTransform/>
											</Button.RenderTransform>
											<Viewbox Width="28" Height="28">
												<Path>
													<Path.Fill>
														<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
															<GradientStop Color="#FF66D9FF" Offset="0"/>
															<GradientStop Color="#FF00BFFF" Offset="0.5"/>
															<GradientStop Color="#FF0077CC" Offset="1"/>
														</LinearGradientBrush>
													</Path.Fill>
													<Path.Data>
														M12,20C7.59,20 4,16.41 4,12C4,7.59 7.59,4 12,4C16.41,4 20,7.59 20,12C20,16.41 16.41,20 12,20M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M7,13H17V11H7
													</Path.Data>
												</Path>
											</Viewbox>
										</Button>
									</StackPanel>
								</StackPanel>
								<Button Name="pCloseButton" Background="#111111" Foreground="#EEEEEE" BorderThickness="0" Content="X" Margin="300,10,10,10" Height="18" Width="22" Template="{StaticResource NoMouseOverButtonTemplate}" Panel.ZIndex="1"/>
							</Grid>
						</Border>
						<Canvas.ContextMenu>
							<ContextMenu Style="{StaticResource CustomContextMenuStyle}">
								<MenuItem Header="    Copy    " Style="{StaticResource MainMenuItemStyle}">
									<MenuItem Header="   IP Address  " Name="PopupContextCopyIP" Style="{StaticResource CustomMenuItemStyle}"/>
									<MenuItem Header="   Hostname    " Name="PopupContextCopyHostname" Style="{StaticResource CustomMenuItemStyle}"/>
									<MenuItem Header="   MAC Address " Name="PopupContextCopyMAC" Style="{StaticResource CustomMenuItemStyle}"/>
									<MenuItem Header="   Vendor      " Name="PopupContextCopyVendor" Style="{StaticResource CustomMenuItemStyle}"/>
									<Separator Background="#222222"/>
									<MenuItem Header="   All         " Name="PopupContextCopyAll" Style="{StaticResource CustomMenuItemStyle}"/>
								</MenuItem>
							</ContextMenu>
						</Canvas.ContextMenu>
					</Canvas>
				</Grid>
				<Grid Name="NetMonContentGrid" Margin="10,10,10,0" Visibility="Hidden" Panel.ZIndex="1">
					<Grid.RowDefinitions>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="*"/>
						<RowDefinition Height="280"/>
					</Grid.RowDefinitions>
					<ComboBox Name="AdapterDropdown" Grid.Row="0" HorizontalAlignment="Left" Width="150" Margin="17,3,0,0" Style="{StaticResource NetMonComboBoxStyle}"/>
					<StackPanel Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,3,10,0">
						<StackPanel Orientation="Horizontal" Margin="5">
							<TextBlock Text="Connection / Performance Monitor" Foreground="#FFFFFFFF" FontSize="12" FontWeight="Bold" Margin="10,0,0,0" HorizontalAlignment="Center"/>
						</StackPanel>
					</StackPanel>
					<StackPanel Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,3,10,0">
						<StackPanel Orientation="Horizontal" Margin="5">
							<Rectangle Width="20" Height="2" Fill="#FF00BFFF" Margin="0,0,5,0"/>
							<TextBlock Text="Download" Foreground="#FFFFFFFF" FontSize="12"/>
						</StackPanel>
						<StackPanel Orientation="Horizontal" Margin="5">
							<Rectangle Width="20" Height="2" Fill="#FFB200B2" Margin="0,0,5,0"/>
							<TextBlock Text="Upload" Foreground="#FFFFFFFF" FontSize="12"/>
						</StackPanel>
					</StackPanel>
					<Grid Grid.Row="1">
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="30"/>
							<ColumnDefinition Width="*"/>
						</Grid.ColumnDefinitions>
						<Grid.RowDefinitions>
							<RowDefinition Height="100"/>
							<RowDefinition Height="Auto"/>
						</Grid.RowDefinitions>
						<TextBlock Name="YAxisTitle" Grid.Column="0" Grid.Row="0" Text="Speed" Foreground="#FFFFFFFF" FontSize="12" Margin="-3,73,0,0">
							<TextBlock.RenderTransform>
								<RotateTransform Angle="-90"/>
							</TextBlock.RenderTransform>
						</TextBlock>
						<Canvas Name="GraphCanvas" Grid.Column="1" Grid.Row="0" Width="830" Height="100" Background="#FF252526" ClipToBounds="True" Margin="-29,13,0,0">
							<TextBlock Name="YLabelMax" Canvas.Left="5" Canvas.Top="0" Foreground="#FFFFFFFF" FontSize="10"/>
							<TextBlock Name="YLabel75" Canvas.Left="5" Canvas.Top="25" Foreground="#FFFFFFFF" FontSize="10"/>
							<TextBlock Name="YLabel50" Canvas.Left="5" Canvas.Top="50" Foreground="#FFFFFFFF" FontSize="10"/>
							<TextBlock Name="YLabel25" Canvas.Left="5" Canvas.Top="75" Foreground="#FFFFFFFF" FontSize="10"/>
						</Canvas>
						<TextBlock Name="XAxisTitle" Grid.Column="1" Grid.Row="1" Text="Time (60s)" Foreground="#FFFFFFFF" FontSize="12" Margin="382,13,0,0"/>
					</Grid>
					<ListView Name="NetMonTCPList" Grid.Row="2" Margin="9,-19,11,18" Style="{StaticResource NetMonListViewStyle}">
						<ListView.View>
							<GridView>
								<GridViewColumn Header="Local Address" DisplayMemberBinding="{Binding LocalAddress}" Width="120" HeaderContainerStyle="{StaticResource NetMonColumnHeaderStyle}"/>
								<GridViewColumn Header="Local Port" DisplayMemberBinding="{Binding LocalPort}" Width="120" HeaderContainerStyle="{StaticResource NetMonColumnHeaderStyle}"/>
								<GridViewColumn Header="Remote Address" DisplayMemberBinding="{Binding RemoteAddress}" Width="120" HeaderContainerStyle="{StaticResource NetMonColumnHeaderStyle}"/>
								<GridViewColumn Header="Remote Port" DisplayMemberBinding="{Binding RemotePort}" Width="120" HeaderContainerStyle="{StaticResource NetMonColumnHeaderStyle}"/>
								<GridViewColumn Header="Process" DisplayMemberBinding="{Binding ProcessName}" Width="375" HeaderContainerStyle="{StaticResource NetMonColumnHeaderStyle}"/>
							</GridView>
						</ListView.View>
					</ListView>
					<TextBlock Name="NetMonTotalConnections" Foreground="{x:Static SystemColors.GrayTextBrush}" FontWeight="Normal" FontSize="11" Margin="0,263,0,0" HorizontalAlignment="Center" Grid.Row="2"/>
				</Grid>
				<Canvas Name="PopupCanvas2" Background="#222222" Visibility="Hidden" Width="330" Height="220" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,40,0,0" Panel.ZIndex="10">
					<Border Name="PopupBorder2" Width="330" Height="220" BorderThickness="0.70" CornerRadius="5" Background="#222222" Opacity="0.95">
						<Border.BorderBrush>
							<SolidColorBrush Color="#CCCCCC"/>
						</Border.BorderBrush>
						<Border.RenderTransform>
							<TransformGroup>
								<ScaleTransform/>
								<SkewTransform/>
								<RotateTransform/>
								<TranslateTransform/>
							</TransformGroup>
						</Border.RenderTransform>
						<Grid>
							<Grid.RowDefinitions>
								<RowDefinition Height="Auto"/>
								<RowDefinition Height="Auto"/>
								<RowDefinition Height="*"/>
								<RowDefinition Height="Auto"/>
							</Grid.RowDefinitions>
							<StackPanel Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,15,0,0" Visibility="Visible">
								<Path Name="subnetIcon" Grid.Row="0" Width="24" Height="24" Margin="0,-2,6,0" Visibility="Collapsed">
									<Path.Effect>
										<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
									</Path.Effect>
									<Path.Fill>
										<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
											<GradientStop Color="#FF66D9FF" Offset="0"/>
											<GradientStop Color="#FF00BFFF" Offset="0.5"/>
											<GradientStop Color="#FF0077CC" Offset="1"/>
										</LinearGradientBrush>
									</Path.Fill>
									<Path.Data>
										M10,2C8.89,2 8,2.89 8,4V7C8,8.11 8.89,9 10,9H11V11H2V13H6V15H5C3.89,15 3,15.89 3,17V20C3,21.11 3.89,22 5,22H9C10.11,22 11,21.11 11,20V17C11,15.89 10.11,15 9,15H8V13H16V15H15C13.89,15 13,15.89 13,17V20C13,21.11 13.89,22 15,22H19C20.11,22 21,21.11 21,20V17C21,15.89 20.11,15 19,15H18V13H22V11H13V9H14C15.11,9 16,8.11 16,7V4C16,2.89 15.11,2 14,2H10M10,4H14V7H10V4M5,17H9V20H5V17M15,17H19V20H15V17Z
									</Path.Data>
								</Path>
								<Path Name="imgPortScan" Grid.Row="0" Width="24" Height="24" Margin="0,-1,5,0" Visibility="Collapsed">
									<Path.Effect>
										<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
									</Path.Effect>
									<Path.Fill>
										<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
											<GradientStop Color="#FF66D9FF" Offset="0"/>
											<GradientStop Color="#FF00BFFF" Offset="0.5"/>
											<GradientStop Color="#FF0077CC" Offset="1"/>
										</LinearGradientBrush>
									</Path.Fill>
									<Path.Data>
										M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5A6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z
									</Path.Data>
								</Path>
								<TextBlock Name="PopupTitle2" HorizontalAlignment="Center" FontSize="14" Foreground="#EEEEEE" FontWeight="Bold"/>
							</StackPanel>
							<TextBlock Name="PopupText2" TextWrapping="Wrap" Margin="10,45,10,0" FontSize="14" Foreground="#EEEEEE" FontWeight="Bold" VerticalAlignment="Top" HorizontalAlignment="Center" Grid.Row="1" Visibility="Collapsed"/>
							<StackPanel Name="SubnetInput" Grid.Row="1" Margin="10,55,10,0" Visibility="Collapsed">
								<StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
									<TextBlock Text="Subnet" FontSize="14" Foreground="#EEEEEE" Margin="-7,2,5,5"/>
									<ComboBox Name="subnetOctet1" Style="{StaticResource CustomComboBoxStyle}"/>
									<ComboBox Name="subnetOctet2" Style="{StaticResource CustomComboBoxStyle}"/>
									<ComboBox Name="subnetOctet3" Style="{StaticResource CustomComboBoxStyle}"/>
									<TextBlock Text="1-254" FontSize="14" Foreground="#EEEEEE" Margin="0,2,0,0"/>
								</StackPanel>
								<Button Name="btnReset" Width="24" Height="24" ToolTip="Reset Subnet" Margin="0,12,0,0" BorderThickness="0" BorderBrush="#FF00BFFF" IsEnabled="True" Background="Transparent" Template="{StaticResource NoMouseOverButtonTemplate}">
									<Button.Effect>
										<DropShadowEffect ShadowDepth="5" BlurRadius="5" Color="Black" Direction="270"/>
									</Button.Effect>
									<Button.Resources>
										<Storyboard x:Key="mouseEnterAnimation">
											<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="-2" Duration="0:0:0.2"/>
											<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="6" Duration="0:0:0.2"/>
											<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="6" Duration="0:0:0.2"/>
										</Storyboard>
										<Storyboard x:Key="mouseLeaveAnimation">
											<DoubleAnimation Storyboard.TargetProperty="RenderTransform.(TranslateTransform.Y)" To="0" Duration="0:0:0.2"/>
											<DoubleAnimation Storyboard.TargetProperty="Effect.ShadowDepth" To="3" Duration="0:0:0.2"/>
											<DoubleAnimation Storyboard.TargetProperty="Effect.BlurRadius" To="3" Duration="0:0:0.2"/>
										</Storyboard>
									</Button.Resources>
									<Button.RenderTransform>
										<TranslateTransform/>
									</Button.RenderTransform>
								<Viewbox Width="19" Height="19">
									<Path>
										<Path.Fill>
											<LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
												<GradientStop Color="#FF66D9FF" Offset="0"/>
												<GradientStop Color="#FF00BFFF" Offset="0.5"/>
												<GradientStop Color="#FF0077CC" Offset="1"/>
											</LinearGradientBrush>
										</Path.Fill>
										<Path.Data>
											M19,8L15,12H18A6,6 0 0,1 12,18C11,18 10.03,17.75 9.2,17.3L7.74,18.76C8.97,19.54 10.43,20 12,20A8,8 0 0,0 20,12H23M6,12A6,6 0 0,1 12,6C13,6 13.97,6.25 14.8,6.7L16.26,5.24C15.03,4.46 13.57,4 12,4A8,8 0 0,0 4,12H1L5,16L9,12
										</Path.Data>
									</Path>
								</Viewbox>
								</Button>
							</StackPanel>
							<StackPanel Orientation="Horizontal" Grid.Row="1" Margin="10,5,10,5" HorizontalAlignment="Center" Visibility="Collapsed" Name="ScanPanel">
								<Button Name="btnScan" Background="#777777" Width="200" Height="25" Margin="0,5,5,0" Template="{StaticResource NoMouseOverButtonTemplate}">
									<Button.Content>
										<TextBlock Name="btnScanText" FontWeight="Bold" HorizontalAlignment="Center"/>
									</Button.Content>
										<Button.BorderBrush>
											<SolidColorBrush x:Name="CycleBrush2" Color="White"/>
										</Button.BorderBrush>
								</Button>
								<Grid>
									<ProgressBar Name="ProgressBar" Foreground="#FF00BFFF" Background="#777777" Width="200" Height="25" Value="0" Minimum="0" Maximum="100" HorizontalAlignment="Left" Margin="0,5,5,0" Visibility="Collapsed"/>
									<TextBlock Name="ProgressText" Foreground="#000000" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold" Margin="0,5,0,0"/>
								</Grid>
								<ComboBox Name="cmbPortRange" Width="98" Height="25" Margin="5,5,0,0" Style="{StaticResource CustomComboBoxStyle2}"/>
							</StackPanel>
							<ListBox Name="ResultsList" Grid.Row="2" Margin="10,10,10,10" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#333333" Foreground="#EEEEEE" Visibility="Collapsed">
								<ListBox.ItemContainerStyle>
									<Style TargetType="{x:Type ListBoxItem}">
										<Setter Property="Background" Value="Transparent" />
										<Setter Property="Foreground" Value="#EEEEEE"/>
										<Setter Property="BorderBrush" Value="Transparent"/>
										<Setter Property="BorderThickness" Value="0.70"/>
										<Setter Property="Template">
											<Setter.Value>
												<ControlTemplate TargetType="{x:Type ListBoxItem}">
													<Border BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Background="{TemplateBinding Background}">
														<ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Content="{TemplateBinding Content}"/>
													</Border>
													<ControlTemplate.Triggers>
														<Trigger Property="ItemsControl.AlternationIndex" Value="0">
															<Setter Property="Background" Value="#111111"/>
															<Setter Property="Foreground" Value="#EEEEEE"/>
														</Trigger>
														<Trigger Property="ItemsControl.AlternationIndex" Value="1">
															<Setter Property="Background" Value="#000000"/>
															<Setter Property="Foreground" Value="#EEEEEE"/>
														</Trigger>
														<Trigger Property="IsMouseOver" Value="True">
															<Setter Property="Background" Value="#4000B7FF"/>
															<Setter Property="Foreground" Value="#EEEEEE"/>
															<Setter Property="BorderBrush" Value="#FF00BFFF"/>
														</Trigger>
														<MultiTrigger>
															<MultiTrigger.Conditions>
																<Condition Property="IsSelected" Value="true"/>
																<Condition Property="Selector.IsSelectionActive" Value="true"/>
															</MultiTrigger.Conditions>
															<Setter Property="Background" Value="#4000B7FF"/>
															<Setter Property="Foreground" Value="#EEEEEE"/>
															<Setter Property="FontWeight" Value="Bold"/>
															<Setter Property="BorderBrush" Value="#FF00BFFF"/>
														</MultiTrigger>
													</ControlTemplate.Triggers>
												</ControlTemplate>
											</Setter.Value>
										</Setter>
									</Style>
								</ListBox.ItemContainerStyle>
								<ListBox.AlternationCount>2</ListBox.AlternationCount>
							</ListBox>
							<Button Name="pCloseButton2" Content="X" Background="#111111" Foreground="#EEEEEE" BorderThickness="0" HorizontalAlignment="Right" Margin="0,5,9,5" Height="18" Width="22" Grid.Row="0" Template="{StaticResource NoMouseOverButtonTemplate}"/>
							<StackPanel Name="ButtonStackPanel2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Grid.Row="3" Margin="0,10,0,10">
								<Button Name="btnOK2" Content="OK" Margin="5,10,5,10" Background="#111111" Foreground="#EEEEEE" Width="75" Height="25" Template="{StaticResource NoMouseOverButtonTemplate}"/>
							</StackPanel>
						</Grid>
					</Border>
				</Canvas>
			</Grid>
		</Grid>
	</Border>
	<Window.Triggers>
		<EventTrigger RoutedEvent="Window.Loaded">
			<BeginStoryboard>
				<Storyboard>
					<ColorAnimationUsingKeyFrames Storyboard.TargetName="CycleBrush" Storyboard.TargetProperty="Color" RepeatBehavior="Forever" Duration="0:0:6">
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:0"/>
						<LinearColorKeyFrame Value="#FF00BFFF" KeyTime="0:0:3"/>
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:6"/>
					</ColorAnimationUsingKeyFrames>
					<ColorAnimationUsingKeyFrames Storyboard.TargetName="CycleBrush2" Storyboard.TargetProperty="Color" RepeatBehavior="Forever" Duration="0:0:6">
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:0"/>
						<LinearColorKeyFrame Value="#FF00BFFF" KeyTime="0:0:3"/>
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:6"/>
					</ColorAnimationUsingKeyFrames>
					<ColorAnimationUsingKeyFrames Storyboard.TargetName="PopupBorder" Storyboard.TargetProperty="BorderBrush.Color" RepeatBehavior="Forever" Duration="0:0:6">
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:0"/>
						<LinearColorKeyFrame Value="#FF00BFFF" KeyTime="0:0:3"/>
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:6"/>
					</ColorAnimationUsingKeyFrames>
					<ColorAnimationUsingKeyFrames Storyboard.TargetName="PopupBorder2" Storyboard.TargetProperty="BorderBrush.Color" RepeatBehavior="Forever" Duration="0:0:6">
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:0"/>
						<LinearColorKeyFrame Value="#FF00BFFF" KeyTime="0:0:3"/>
						<LinearColorKeyFrame Value="#CCCCCC" KeyTime="0:0:6"/>
					</ColorAnimationUsingKeyFrames>
				</Storyboard>
			</BeginStoryboard>
		</EventTrigger>
	</Window.Triggers>
	<Window.TaskbarItemInfo>
		<TaskbarItemInfo/>
	</Window.TaskbarItemInfo>
</Window>
'@

# Load XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try{$Main = [Windows.Markup.XamlReader]::Load( $reader )}
catch{$shell = New-Object -ComObject Wscript.Shell; $shell.Popup("$_",0,'XAML ERROR:',0x0) | Out-Null; Exit}

# Store Form Objects In PowerShell
$xaml.SelectNodes("//*[@Name]") | %{Set-Variable -Name "$($_.Name)" -Value $Main.FindName($_.Name)}

# Set Title
$Main.Title = "$AppId"
$titleBar.Text = "$AppId"

# Window Closing
$Main.Add_Closing({
	if ($global:timer) {
		try { $global:timer.Stop() } catch { Write-Host "Error stopping timer: $_" }
	}
	if ($Runspace) {
		try {
			$global:Runspace.EndInvoke($global:netMonHandle)
			$global:Runspace.Dispose()
		} catch { Write-Host "Error disposing netMonHandle: $_" }
	}
	Get-Job | Remove-Job -Force
	if ($RunspacePool) {
		try { $RunspacePool.Close(); $RunspacePool.Dispose() } catch { Write-Host "Error disposing RunspacePool: $_" }
	}
	$Main.Add_Closed({ [Environment]::Exit(0) })
})

$Main.Add_ContentRendered({
	# Define icons
	$icons = @(
		@{File = 'C:\Windows\System32\imageres.dll'; Index = 73; ElementName = "scanAdminIcon"; Type = "Image"},
		@{File = 'C:\Windows\System32\mstscax.dll'; Index = 0; ElementName = "btnRDP"; Type = "Button"},
		@{File = 'C:\Windows\System32\shell32.dll'; Index = 13; ElementName = "btnWebInterface"; Type = "Button"},
		@{File = 'C:\Windows\System32\shell32.dll'; Index = 266; ElementName = "btnShare"; Type = "Button"}
	)

	# Extract and set icons
	foreach ($icon in $icons) {
		$extractedIcon = [System.IconExtractor]::Extract($icon.File, $icon.Index, $true)
		if ($extractedIcon) {
			$bitmapSource = [System.IconExtractor]::IconToBitmapSource($extractedIcon)
			$element = $Main.FindName($icon.ElementName)

			switch ($icon.Type) {
				"Image" {
					$element.Source = $bitmapSource
					$element.SetValue([System.Windows.Media.RenderOptions]::BitmapScalingModeProperty, [System.Windows.Media.BitmapScalingMode]::HighQuality)
				}
				"Button" {
					$imageWidth = 24
					$imageHeight = 24
					$image = New-Object System.Windows.Controls.Image -Property @{
						Source = $bitmapSource;
						Width = $imageWidth;
						Height = $imageHeight;
						Stretch = [System.Windows.Media.Stretch]::Fill
					}
					$image.SetValue([System.Windows.Media.RenderOptions]::BitmapScalingModeProperty, [System.Windows.Media.BitmapScalingMode]::HighQuality)
					$element.Content = $image
				}
			}
		}
	}

	# Populate the ComboBoxes
	function Initialize-IPCombo {
		param($comboBox)
		for ($i = 0; $i -le 255; $i++) {
			$comboBox.Items.Add($i)
		}
		$comboBox.SelectedIndex = 0
	}

	# Initialize Comboboxes
	@('subnetOctet1', 'subnetOctet2', 'subnetOctet3') | ForEach-Object {
		Initialize-IPCombo -comboBox ($Main.FindName($_))
	}

	# Register ToggleMonitorButton mouse event handlers
	$ToggleMonitorButton.Add_MouseEnter({
		$storyboard = $ToggleMonitorButton.Resources["mouseEnterAnimation"]
		$storyboard.Begin($ToggleMonitorButton)
	})
	$ToggleMonitorButton.Add_MouseLeave({
		$storyboard = $ToggleMonitorButton.Resources["mouseLeaveAnimation"]
		$storyboard.Begin($ToggleMonitorButton)
	})

	# Initialize Monitor Mode Variables
	$global:adapters = @()
	$global:adapterStats = @{}
	$global:speedHistory = @{}
	$global:lastTime = $null
	$global:canvasWidth = 830
	$global:canvasHeight = 100
	$global:maxPoints = 60
	$global:historySize = 2
	$global:resetThreshold = 100000
	$global:maxSpeed = 1000
	$global:LastSelectedItem = $null

	# Start Monitor Mode Background Task
	try {
		if (-not $RunspacePool) {
			Show-Popup2 -Message "RunspacePool is not initialized." -Title "Error:"
			return
		}
		if ($RunspacePool.RunspacePoolStateInfo.State -ne 'Opened') {
			Show-Popup2 -Message "RunspacePool is not open." -Title "Error:"
			return
		}
		$global:netMonHandle = Start-NetMonBackgroundTask
	} catch {
		Show-Popup2 -Message "Failed to start Monitor Mode background task: $_" -Title "Error:"
		return
	}

	# Initialize Adapters
	try {
		$initialAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Loopback*" -and $_.InterfaceDescription -notlike "*ISATAP*" }
		if (-not $initialAdapters) {
			Show-Popup2 -Message "No network adapters available." -Title "Error:"
			return
		}
		foreach ($adapter in $initialAdapters) {
			$adapterName = $adapter.Name
			$global:adapters += $adapterName
			$global:adapterStats[$adapterName] = @{
				RxHistory = @()
				TxHistory = @()
				TimeHistory = @()
				LastRxBytes = 0
				LastTxBytes = 0
			}
			$global:speedHistory[$adapterName] = @{
				RxSpeeds = @()
				TxSpeeds = @()
			}
			if ($AdapterDropdown) {
				$AdapterDropdown.Items.Add($adapterName) | Out-Null
			}
		}
		if ($AdapterDropdown -and $AdapterDropdown.Items.Count -gt 0) {
			$AdapterDropdown.SelectedIndex = 0
		}
	} catch {
		Show-Popup2 -Message "Error initializing adapters: $_" -Title "Error:"
	}

	# Initialize Timer
	$global:timer = New-Object System.Windows.Threading.DispatcherTimer
	$global:timer.Interval = [TimeSpan]::FromMilliseconds(1000)
	$global:timer.Add_Tick({
		try {
			if ($global:syncHash.Error) {
				if ($NetMonContentGrid -and $NetMonContentGrid.Visibility -eq [System.Windows.Visibility]::Visible) {
					Show-Popup2 -Message "Background task error: $($global:syncHash.Error)" -Title "Error:"
				}
				return
			}
			$statsPerAdapter = $global:syncHash.NetworkStats
			$tcpConnections = $global:syncHash.TCPConnections
			$currentTime = [DateTime]::Now
			if ($null -eq $global:lastTime) { $global:lastTime = $currentTime }
			$deltaTime = [Math]::Max(0.2, ($currentTime - $global:lastTime).TotalSeconds)
			$global:lastTime = $currentTime

			foreach ($adapterName in $global:adapters) {
				$adapterStat = $global:adapterStats[$adapterName]
				if ($statsPerAdapter.ContainsKey($adapterName)) {
					$currentStats = $statsPerAdapter[$adapterName]
					$rxBytes = $currentStats.RxBytes
					$txBytes = $currentStats.TxBytes
					$timestamp = $currentStats.Timestamp

					if ($adapterStat.LastRxBytes -gt 0 -and $adapterStat.LastTxBytes -gt 0) {
						$resetRx = $rxBytes -lt $adapterStat.LastRxBytes -and ($adapterStat.LastRxBytes - $rxBytes) -gt $global:resetThreshold
						$resetTx = $txBytes -lt $adapterStat.LastTxBytes -and ($adapterStat.LastTxBytes - $txBytes) -gt $global:resetThreshold
						if ($resetRx -or $resetTx) {
							$adapterStat.RxHistory = @()
							$adapterStat.TxHistory = @()
							$adapterStat.TimeHistory = @()
							$global:speedHistory[$adapterName].RxSpeeds = @()
							$global:speedHistory[$adapterName].TxSpeeds = @()
						}
					}

					$adapterStat.RxHistory += $rxBytes
					$adapterStat.TxHistory += $txBytes
					$adapterStat.TimeHistory += $timestamp
					if ($adapterStat.RxHistory.Count -gt $global:historySize) {
						$adapterStat.RxHistory = $adapterStat.RxHistory | Select-Object -Last $global:historySize
						$adapterStat.TxHistory = $adapterStat.TxHistory | Select-Object -Last $global:historySize
						$adapterStat.TimeHistory = $adapterStat.TimeHistory | Select-Object -Last $global:historySize
					}
					$adapterStat.LastRxBytes = $rxBytes
					$adapterStat.LastTxBytes = $txBytes

					$rxSpeed = 0
					$txSpeed = 0
					if ($adapterStat.RxHistory.Count -ge 2 -and $adapterStat.TimeHistory.Count -ge 2) {
						$totalRxDiff = 0
						$totalTxDiff = 0
						$totalTicks = 0
						for ($i = 1; $i -lt $adapterStat.RxHistory.Count; $i++) {
							$rxDiff = [double]($adapterStat.RxHistory[$i] - $adapterStat.RxHistory[$i-1])
							$txDiff = [double]($adapterStat.TxHistory[$i] - $adapterStat.TxHistory[$i-1])
							$tickDiff = [double]($adapterStat.TimeHistory[$i] - $adapterStat.TimeHistory[$i-1])
							$totalRxDiff += $rxDiff
							$totalTxDiff += $txDiff
							$totalTicks += $tickDiff
						}
						$totalTime = $totalTicks / 10000000.0
						if ($totalTime -gt 0) {
							$rxSpeed = [Math]::Max(0, $totalRxDiff / $totalTime / 1024)
							$txSpeed = [Math]::Max(0, $totalTxDiff / $totalTime / 1024)
						}
					}

					$global:speedHistory[$adapterName].RxSpeeds += $rxSpeed
					$global:speedHistory[$adapterName].TxSpeeds += $txSpeed
					if ($global:speedHistory[$adapterName].RxSpeeds.Count -gt $global:maxPoints) {
						$global:speedHistory[$adapterName].RxSpeeds = $global:speedHistory[$adapterName].RxSpeeds | Select-Object -Last $global:maxPoints
						$global:speedHistory[$adapterName].TxSpeeds = $global:speedHistory[$adapterName].TxSpeeds | Select-Object -Last $global:maxPoints
					}
				}
			}

			if ($NetMonContentGrid -and $NetMonContentGrid.Visibility -eq [System.Windows.Visibility]::Visible) {
				$Main.Dispatcher.Invoke([Action]{
					if (-not $GraphCanvas -or -not $YLabelMax -or -not $YLabel75 -or -not $YLabel50 -or -not $YLabel25 -or -not $NetMonTCPList) {
						return
					}

					$childrenToRemove = $GraphCanvas.Children | Where-Object { $_.GetType().Name -eq "Line" }
					foreach ($child in $childrenToRemove) { $GraphCanvas.Children.Remove($child) }

					$selectedAdapter = if ($AdapterDropdown -and $AdapterDropdown.Items.Count -gt 0) { $AdapterDropdown.SelectedItem } else { $global:adapters[0] }
					if (-not $selectedAdapter) {
						Show-Popup2 -Message "No adapter selected." -Title "Warning:"
						return
					}

					$rxSpeeds = $global:speedHistory[$selectedAdapter].RxSpeeds
					$txSpeeds = $global:speedHistory[$selectedAdapter].TxSpeeds

					$maxRx = if ($rxSpeeds) { ($rxSpeeds | Measure-Object -Maximum).Maximum } else { 0 }
					$maxTx = if ($txSpeeds) { ($txSpeeds | Measure-Object -Maximum).Maximum } else { 0 }
					$maxSpeedCalc = [Math]::Max($maxRx, $maxTx)

					if ($maxSpeedCalc -le 25) { $global:maxSpeed = 25 }
					elseif ($maxSpeedCalc -le 250) { $global:maxSpeed = 250 }
					elseif ($maxSpeedCalc -le 500) { $global:maxSpeed = 500 }
					elseif ($maxSpeedCalc -le 1000) { $global:maxSpeed = 1000 }
					else { $global:maxSpeed = [Math]::Ceiling($maxSpeedCalc / 250) * 250 }

					$YLabelMax.Text = Format-Speed -speedInKBs $global:maxSpeed
					$YLabel75.Text = Format-Speed -speedInKBs ($global:maxSpeed * 0.75)
					$YLabel50.Text = Format-Speed -speedInKBs ($global:maxSpeed * 0.5)
					$YLabel25.Text = Format-Speed -speedInKBs ($global:maxSpeed * 0.25)

					$yScale = $global:canvasHeight / $global:maxSpeed
					$xScale = $global:canvasWidth / $global:maxPoints

					for ($i = 1; $i -le 3; $i++) {
						$gridLine = New-Object System.Windows.Shapes.Line
						$gridLine.X1 = 0
						$gridLine.X2 = $global:canvasWidth
						$gridLine.Y1 = $i * ($global:canvasHeight / 4)
						$gridLine.Y2 = $i * ($global:canvasHeight / 4)
						$gridLine.Stroke = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromRgb(63, 63, 70))
						$gridLine.StrokeThickness = 1
						$GraphCanvas.Children.Add($gridLine)
					}

					for ($i = 1; $i -lt $rxSpeeds.Count; $i++) {
						$x1 = $global:canvasWidth - ($rxSpeeds.Count - $i) * $xScale
						$y1 = $global:canvasHeight - ($rxSpeeds[$i-1] * $yScale)
						$x2 = $global:canvasWidth - ($rxSpeeds.Count - 1 - $i) * $xScale
						$y2 = $global:canvasHeight - ($rxSpeeds[$i] * $yScale)
						$line = New-Object System.Windows.Shapes.Line
						$line.X1 = $x1; $line.Y1 = $y1; $line.X2 = $x2; $line.Y2 = $y2
						$line.Stroke = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromRgb(0, 191, 255))
						$line.StrokeThickness = 2
						$GraphCanvas.Children.Add($line)
					}

					for ($i = 1; $i -lt $txSpeeds.Count; $i++) {
						$x1 = $global:canvasWidth - ($txSpeeds.Count - $i) * $xScale
						$y1 = $global:canvasHeight - ($txSpeeds[$i-1] * $yScale)
						$x2 = $global:canvasWidth - ($txSpeeds.Count - 1 - $i) * $xScale
						$y2 = $global:canvasHeight - ($txSpeeds[$i] * $yScale)
						$line = New-Object System.Windows.Shapes.Line
						$line.X1 = $x1; $line.Y1 = $y1; $line.X2 = $x2; $line.Y2 = $y2
						$line.Stroke = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromRgb(178, 0, 178))
						$line.StrokeThickness = 2
						$GraphCanvas.Children.Add($line)
					}

					if ($tcpConnections) {
						$NetMonTCPList.ItemsSource = $tcpConnections
						$NetMonTotalConnections.Text = "$($tcpConnections.Count) active connections"

						if ($global:LastSelectedItem) {
							foreach ($item in $NetMonTCPList.Items) {
								# Compare key properties to find the matching item
								if ($item.LocalAddress -eq $global:LastSelectedItem.LocalAddress -and
									$item.LocalPort -eq $global:LastSelectedItem.LocalPort -and
									$item.RemoteAddress -eq $global:LastSelectedItem.RemoteAddress -and
									$item.RemotePort -eq $global:LastSelectedItem.RemotePort -and
									$item.ProcessName -eq $global:LastSelectedItem.ProcessName) {
									$NetMonTCPList.SelectedItem = $item
									break
								}
							}
						}
					}
				}, [System.Windows.Threading.DispatcherPriority]::Render)
			}
		} catch {
			if ($NetMonContentGrid -and $NetMonContentGrid.Visibility -eq [System.Windows.Visibility]::Visible) {
				Show-Popup2 -Message "UI update error: $_" -Title "Error:"
			}
		}
	})

	# Start Timer
	$global:timer.Start()

	# Toggle Scanner/Monitor Mode button Click Handler
	$ToggleMonitorButton.Add_Click({
		try {
			if (-not $NetMonContentGrid -or -not $IPScannerContentGrid -or -not $HideGraphic -or -not $ShowGraphic) {
				Show-Popup2 -Message "UI elements not found." -Title "Error:"
				return
			}
			if ($NetMonContentGrid.Visibility -eq [System.Windows.Visibility]::Visible) {
				$ToggleMonitorButton.ToolTip = "Monitor Mode"
				$NetMonContentGrid.Visibility = [System.Windows.Visibility]::Hidden
				$IPScannerContentGrid.Visibility = [System.Windows.Visibility]::Visible
				$HideGraphic.Visibility = [System.Windows.Visibility]::Hidden
				$ShowGraphic.Visibility = [System.Windows.Visibility]::Visible
			} else {
				$ToggleMonitorButton.ToolTip = "Scanner Mode"
				$NetMonContentGrid.Visibility = [System.Windows.Visibility]::Visible
				$IPScannerContentGrid.Visibility = [System.Windows.Visibility]::Hidden
				$HideGraphic.Visibility = [System.Windows.Visibility]::Visible
				$ShowGraphic.Visibility = [System.Windows.Visibility]::Hidden
			}
		} catch {
			Show-Popup2 -Message "Error toggling view: $_" -Title "Error:"
		}
	})

	# Monitor Mode Context Menu Handlers
	$contextMenuElements = @('NetMonExportContext', 'CopyLocalAddress', 'CopyLocalPort', 'CopyRemoteAddress', 'CopyRemotePort', 'CopyProcessName', 'CopyAll', 'NetMonExportToHTML', 'NetMonExportToCSV', 'NetMonExportToText')

	$NetMonTCPList.Add_SelectionChanged({
		$NetMonExportContext.IsEnabled = $NetMonTCPList.Items.Count -gt 0
	})

	$NetMonTCPList.Add_PreviewMouseLeftButtonUp({
		param($sender, $e)
		$originalSource = $e.OriginalSource
		$listViewItem = $null
		$currentElement = $originalSource
		while ($currentElement -ne $null -and $listViewItem -eq $null) {
			if ($currentElement -is [System.Windows.Controls.ListViewItem]) { $listViewItem = $currentElement }
			$currentElement = [System.Windows.Media.VisualTreeHelper]::GetParent($currentElement)
		}
		if ($listViewItem -ne $null) {
			$NetMonTCPList.SelectedItems.Clear()
			$listViewItem.IsSelected = $true
			$global:LastSelectedItem = $listViewItem.Content
		}
		$e.Handled = $true
	})

	$NetMonTCPList.Add_PreviewMouseRightButtonDown({
		param($sender, $e)
		$originalSource = $e.OriginalSource
		$listViewItem = $null
		$currentElement = $originalSource
		while ($currentElement -ne $null -and $listViewItem -eq $null) {
			if ($currentElement -is [System.Windows.Controls.ListViewItem]) { $listViewItem = $currentElement }
			$currentElement = [System.Windows.Media.VisualTreeHelper]::GetParent($currentElement)
		}
		$NetMonTCPList.SelectedItems.Clear()
		if ($listViewItem -ne $null) { $listViewItem.IsSelected = $true }
		$NetMonTCPList.ContextMenu = $Main.FindResource("NetMonRightClickContextMenu")
		$NetMonTCPList.ContextMenu.IsOpen = $true
		$e.Handled = $true
	})

	$NetMonTCPList.Add_MouseDoubleClick({
		param($sender, $e)
		$originalSource = $e.OriginalSource
		$listViewItem = $null
		$currentElement = $originalSource
		while ($currentElement -ne $null -and $listViewItem -eq $null) {
			if ($currentElement -is [System.Windows.Controls.ListViewItem]) { $listViewItem = $currentElement }
			$currentElement = [System.Windows.Media.VisualTreeHelper]::GetParent($currentElement)
		}
		$NetMonTCPList.SelectedItems.Clear()
		if ($listViewItem -ne $null) {
			$listViewItem.IsSelected = $true
			$global:LastSelectedItem = $listViewItem.Content
			$NetMonTCPList.ContextMenu = $Main.FindResource("NetMonDoubleClickContextMenu")
			$NetMonTCPList.ContextMenu.IsOpen = $true
		}
		$e.Handled = $true
	})

	$CopyLocalAddress.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) { Set-Clipboard -Value $item.LocalAddress; Show-Popup2 -Message "Local Address copied!" -Title "Info:" }
		else { Show-Popup2 -Message "No item selected!" -Title "Warning:" }
	})

	$CopyLocalPort.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) { Set-Clipboard -Value $item.LocalPort; Show-Popup2 -Message "Local Port copied!" -Title "Info:" }
		else { Show-Popup2 -Message "No item selected!" -Title "Warning:" }
	})

	$CopyRemoteAddress.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) { Set-Clipboard -Value $item.RemoteAddress; Show-Popup2 -Message "Remote Address copied!" -Title "Info:" }
		else { Show-Popup2 -Message "No item selected!" -Title "Warning:" }
	})

	$CopyRemotePort.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) { Set-Clipboard -Value $item.RemotePort; Show-Popup2 -Message "Remote Port copied!" -Title "Info:" }
		else { Show-Popup2 -Message "No item selected!" -Title "Warning:" }
	})

	$CopyProcessName.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) { Set-Clipboard -Value $item.ProcessName; Show-Popup2 -Message "Process Name copied!" -Title "Info:" }
		else { Show-Popup2 -Message "No item selected!" -Title "Warning:" }
	})

	$CopyAll.Add_Click({
		$item = if ($NetMonTCPList.SelectedItem) { $NetMonTCPList.SelectedItem } else { $global:LastSelectedItem }
		if ($item) {
			$details = "Local Address: $($item.LocalAddress)`nLocal Port: $($item.LocalPort)`nRemote Address: $($item.RemoteAddress)`nRemote Port: $($item.RemotePort)`nProcess Name: $($item.ProcessName)"
			Set-Clipboard -Value $details
			Show-Popup2 -Message "All details copied!" -Title "Info:"
		} else {
			Show-Popup2 -Message "No item selected!" -Title "Warning:"
		}
	})

	$NetMonExportToHTML.Add_Click({
		if ($NetMonTCPList.Items.Count -eq 0) { Show-Popup2 -Message "No data to export!" -Title "Warning:"; return }
		$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
		$saveFileDialog.Filter = "HTML files (*.html)|*.html|All files (*.*)|*.*"
		$saveFileDialog.FileName = "TCP_Connections"
		if ($saveFileDialog.ShowDialog() -eq "OK") {
			$path = $saveFileDialog.FileName
			try {
				$htmlContent = "<!DOCTYPE html><html><head><title>TCP Connections</title><style>table, th, td { border: 1px solid black; border-collapse: collapse; padding: 5px; } th { background-color: #f2f2f2; } h1, p { margin: 0; padding: 0; } p { margin-bottom: 2px; } .info-block { margin-bottom: 20px; }</style></head><body><h1>TCP Connections</h1><br><div class='info-block'><p><strong>Date/Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p><p><strong>Total Connections:</strong> $($NetMonTCPList.Items.Count)</p></div><table><tr><th>Local Address</th><th>Local Port</th><th>Remote Address</th><th>Remote Port</th><th>Process Name</th></tr>"
				$NetMonTCPList.Items | ForEach-Object { $htmlContent += "<tr><td>$($_.LocalAddress)</td><td>$($_.LocalPort)</td><td>$($_.RemoteAddress)</td><td>$($_.RemotePort)</td><td>$($_.ProcessName)</td></tr>" }
				$htmlContent += "</table></body></html>"
				[System.IO.File]::WriteAllText($path, $htmlContent)
				Show-Popup2 -Message "Export to HTML completed!" -Title "Export:"
			} catch {
				Show-Popup2 -Message "Error during export: $_" -Title "ERROR:"
			}
		}
	})

	$NetMonExportToCSV.Add_Click({
		if ($NetMonTCPList.Items.Count -eq 0) { Show-Popup2 -Message "No data to export!" -Title "Warning:"; return }
		$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
		$saveFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
		$saveFileDialog.FileName = "TCP_Connections"
		if ($saveFileDialog.ShowDialog() -eq "OK") {
			$path = $saveFileDialog.FileName
			try {
				$csvHeader = "Local Address,Local Port,Remote Address,Remote Port,Process Name"
				$csvContent = $NetMonTCPList.Items | ForEach-Object { "`r`n$($_.LocalAddress.Replace(',','')),$($_.LocalPort),$($_.RemoteAddress.Replace(',','')),$($_.RemotePort),$($_.ProcessName.Replace(',',''))" }
				[System.IO.File]::WriteAllLines($path, ($csvHeader + $csvContent))
				Show-Popup2 -Message "Export to CSV completed!" -Title "Export:"
			} catch {
				Show-Popup2 -Message "Error during export: $_" -Title "ERROR:"
			}
		}
	})

	$NetMonExportToText.Add_Click({
		if ($NetMonTCPList.Items.Count -eq 0) { Show-Popup2 -Message "No data to export!" -Title "Warning:"; return }
		$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
		$saveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
		$saveFileDialog.FileName = "TCP_Connections"
		if ($saveFileDialog.ShowDialog() -eq "OK") {
			$path = $saveFileDialog.FileName
			try {
				$textContent = "TCP CONNECTIONS`n`nDATE/TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nTOTAL CONNECTIONS: $($NetMonTCPList.Items.Count)`n`n--------------------------------------`n"
				$textContent += $NetMonTCPList.Items | ForEach-Object { "Local Address: $($_.LocalAddress)`nLocal Port: $($_.LocalPort)`nRemote Address: $($_.RemoteAddress)`nRemote Port: $($_.RemotePort)`nProcess Name: $($_.ProcessName)`n--------------------------------------`n" }
				[System.IO.File]::WriteAllText($path, $textContent)
				Show-Popup2 -Message "Export to Text completed!" -Title "Export:"
			} catch {
				Show-Popup2 -Message "Error during export: $_" -Title "ERROR:"
			}
		}
	})

	# Bring window to foreground
	$Main.Dispatcher.Invoke([action]{
		$Main.Activate()
	}, [Windows.Threading.DispatcherPriority]::Background)
})

# Center main window
$screen = [System.Windows.SystemParameters]::WorkArea
$windowLeft = ($screen.Width - $Main.Width) / 2
$windowTop = ($screen.Height - $Main.Height) / 2
$Main.Left = $windowLeft
$Main.Top = $windowTop

$btnMinimize.Add_Click({
	$Main.WindowState = [System.Windows.WindowState]::Minimized
})

$btnMinimize.Add_MouseEnter({
	$btnMinimize.Background='#BBBBBB'
})
$btnMinimize.Add_MouseLeave({
	$btnMinimize.Background='#DDDDDD'
})

$btnClose.Add_Click({
	$Main.Close()
})

$btnClose.Add_MouseEnter({
	$btnClose.Background='#ff0000'
})
$btnClose.Add_MouseLeave({
	$btnClose.Background='#DDDDDD'
})

$Main.Add_MouseLeftButtonDown({
	$Main.DragMove()
})

$pCloseButton.Add_Click({
	$PopupCanvas.Visibility = 'Hidden'
})

$pCloseButton.Add_MouseEnter({
	$pCloseButton.Background='#ff0000'
})
$pCloseButton.Add_MouseLeave({
	$pCloseButton.Background='#111111'
})

$pCloseButton2.Add_Click({
	$PopupCanvas2.Visibility = 'Hidden'
	if(-not $btnScan.IsEnabled){
		$global:abortscan = $true
		$ProgressText.Visibility = 'Collapsed'
		$btnScan.Visibility = 'Visible'
		$ProgressBar.Visibility = 'Collapsed'
		$ProgressBar.Value = 0
		Update-uiMain
		$btnScan.IsEnabled = $true
		$Scan.IsEnabled = $true
	}
	$global:CtrlIsDown = $false
	if ($global:gatewayPrefix -ne $originalGatewayPrefix) {
			$scanButtonText.Text = 'Custom Scan'
	} else {
		$scanButtonText.Text = 'Scan'
	}
	$scanAdminIcon.Visibility = 'Collapsed'
})

$pCloseButton2.Add_MouseEnter({
	$pCloseButton2.Background='#ff0000'
})
$pCloseButton2.Add_MouseLeave({
	$pCloseButton2.Background='#111111'
})

function Show-SubnetPopup {
	$btnOK2.Visibility = 'Visible'
	$PopupTitle2.Text = 'Segment Exploration'
	$PopupText2.Visibility = 'Collapsed'
	$SubnetInput.Visibility = 'Visible'
	$ScanPanel.Visibility = 'Collapsed'
	$ResultsList.Visibility = 'Collapsed'
	$imgPortScan.Visibility = 'Collapsed'
	$subnetIcon.Visibility = 'Visible'
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [System.Windows.Controls.Canvas]::GetLeft($listView) + 10)
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::TopProperty, [System.Windows.Controls.Canvas]::GetTop($listView) + 10)
	$PopupCanvas2.Visibility = 'Visible'
}

function Show-PortScanPopup {
	$btnOK2.Visibility = 'Collapsed'
	$PopupTitle2.Text = "$global:target"
	$SubnetInput.Visibility = 'Collapsed'
	$ScanPanel.Visibility = 'Visible'
	$ResultsList.Visibility = 'Visible'
	$imgPortScan.Visibility = 'Visible'
	$subnetIcon.Visibility = 'Collapsed'
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [System.Windows.Controls.Canvas]::GetLeft($listView) + 10)
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::TopProperty, [System.Windows.Controls.Canvas]::GetTop($listView) + 10)
	$PopupCanvas2.Visibility = 'Visible'
}

function Show-Popup2 {
	param (
		[string]$Message,
		[string]$Title = 'Info',
		[bool]$IsSubnetPopup = $false
	)
	$SubnetInput.Visibility = 'Collapsed'
	$ScanPanel.Visibility = 'Collapsed'
	$ResultsList.Visibility = 'Collapsed'
	$PopupText2.Visibility = 'Visible'
	$btnOK2.Visibility = 'Visible'

	$PopupTitle2.Text = $Title
	$PopupText2.Text = $Message

	$centerX = ($Main.ActualWidth - $PopupBorder2.ActualWidth) / 2
	$centerY = ($Main.ActualHeight - $PopupBorder2.ActualHeight) / 2
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [System.Windows.Controls.Canvas]::GetLeft($listView) + 10)
	$PopupCanvas2.SetValue([System.Windows.Controls.Canvas]::TopProperty, [System.Windows.Controls.Canvas]::GetTop($listView) + 10)

	$PopupCanvas2.Visibility = 'Visible'
}

$btnPortScan.Add_Click({
	$global:target = $pIP.Text -replace 'IP: '

	# Set multi-popup for portscan
	Show-PortScanPopup
	$PopupText2.Visibility = 'Collapsed'
	$SubnetInput.Visibility = 'Collapsed'

	# Show port scanning elements
	$btnScan.Visibility = 'Visible'
	$btnScanText.Text = 'Scan Ports'
	$ProgressBar.Visibility = 'Collapsed'
	$ProgressText.Visibility = 'Visible'
	$ProgressText.Text = ''
	$cmbPortRange.Visibility = 'Visible'
	$ResultsList.Visibility = 'Visible'
	$ResultsList.Items.Clear()
	$PopupCanvas2.Visibility = 'Visible'

	$btnOK2.Content = 'OK'
	$ButtonStackPanel2.Visibility = 'Visible'

	# Initialize combobox if not already done
	if ($cmbPortRange.Items.Count -eq 0) {
		for ($start = 1; $start -le 65535; $start += 4000) {
			$end = [Math]::Min($start + 3999, 65535)
			$range = "$start-$end"
			$cmbPortRange.Items.Add($range) | Out-Null
		}
		$cmbPortRange.SelectedIndex = 0
	}
})

$btnScan.Add_Click({
	$btnScan.IsEnabled = $false
	$Scan.IsEnabled = $false
	# Check if anything is selected in the ComboBox
	if ($cmbPortRange.SelectedIndex -ge 0) {
		$selectedRange = $cmbPortRange.SelectedItem.ToString()
		$portRange = $selectedRange -split '-' | ForEach-Object {[int]$_}
		$startPort, $endPort = $portRange
		$totalPorts = $endPort - $startPort + 1

		if($ResultsList.Items){
			$ResultsList.Items.Clear()
		}
		$openPorts = @()
		$ProgressText.Text = 'Scanning Ports'
		$btnScan.Visibility = 'Collapsed'
		$ProgressBar.Visibility = 'Visible'
		$ProgressText.Visibility = 'Visible'
		Update-uiMain

		for ($port = $startPort; $port -le $endPort; $port++) {
			$result = Test-Port -computer $global:target -port $port
			if ($result) {
				$openPorts += $result
				$ResultsList.Items.Add($result)
			}
			$progress = (($port - $startPort + 1) / $totalPorts) * 100
			$ProgressBar.Value = $progress
			Update-uiMain
			if($abortscan){
				$ResultsList.Items.Clear()
				Update-uiMain
				$global:abortscan = $false
				break
			}
		}

		if ($openPorts.Count -eq 0) {
			$ResultsList.Items.Add("No open ports found in the specified range.")
		}
		$ProgressText.Visibility = 'Collapsed'
		$btnScan.Visibility = 'Visible'
		$ProgressBar.Visibility = 'Collapsed'
		$ProgressBar.Value = 0
		Update-uiMain
	} else {
		$ResultsList.Items.Add("Please select a port range.")
	}
	$btnScan.IsEnabled = $true
	$Scan.IsEnabled = $true
})

# Window Icon
$windowIcon = [System.IconExtractor]::Extract('C:\Windows\System32\shell32.dll', 18, $true)
if ($windowIcon) {
	$bitmapSource = [System.IconExtractor]::IconToBitmapSource($windowIcon)
	$Main.Icon = $bitmapSource
	$Main.TaskbarItemInfo.Overlay = $bitmapSource
	$Main.TaskbarItemInfo.Description = $AppId
	($Main.FindName('WindowIconImage')).Source = $bitmapSource
	($Main.FindName('WindowIconImage')).SetValue([System.Windows.Media.RenderOptions]::BitmapScalingModeProperty, [System.Windows.Media.BitmapScalingMode]::HighQuality)
}

$ChangeSubnet.Add_Click({
	$parts = $global:gatewayPrefix -split '\.'
	if ($parts.Length -ge 3) {
		$subnetOctet1.SelectedItem = [int]$parts[0]
		$subnetOctet2.SelectedItem = [int]$parts[1]
		$subnetOctet3.SelectedItem = [int]$parts[2]
	} else {
		$subnetOctet1.SelectedItem = 192
		$subnetOctet2.SelectedItem = 168
		$subnetOctet3.SelectedItem = 1
	}
	Show-SubnetPopup
})

$btnReset.Add_Click({
	if ($originalGatewayPrefix) {
		$parts = $originalGatewayPrefix -split '\.'
		if ($parts.Length -ge 3) {
			$subnetOctet1.SelectedItem = [int]$parts[0]
			$subnetOctet2.SelectedItem = [int]$parts[1]
			$subnetOctet3.SelectedItem = [int]$parts[2]
			$global:gatewayPrefix = $originalGatewayPrefix
		}
	}
})

$btnOK2.Add_Click({
	if ($SubnetInput.Visibility -eq 'Visible') {
		$global:gatewayPrefix = "{0}.{1}.{2}." -f $subnetOctet1.SelectedItem, $subnetOctet2.SelectedItem, $subnetOctet3.SelectedItem
	}
	$global:CtrlIsDown = $false
	if ($global:gatewayPrefix -ne $originalGatewayPrefix) {
			$scanButtonText.Text = 'Custom Scan'
	} else {
		$scanButtonText.Text = 'Scan'
	}
	$scanAdminIcon.Visibility = 'Collapsed'
	$PopupCanvas2.Visibility = 'Hidden'
})

$btnOK2.Add_MouseEnter({
	$btnOK2.Foreground='#000000'
	$btnOK2.Background='#CCCCCC'
})
$btnOK2.Add_MouseLeave({
	$btnOK2.Foreground='#EEEEEE'
	$btnOK2.Background='#111111'
})

$btnRDP.Add_Click({
	&mstsc /v:$tryToConnect
})

$btnWebInterface.Add_Click({
	# Priority order: HTTP/HTTPS
	if($script:httpAvailable -eq 1){
		Start-Process "`"http://$tryToConnect`""
	} else {
		Start-Process "`"https://$tryToConnect`""
	}
})

$btnShare.Add_Click({
	&explorer "`"\\$tryToConnect`""
})

# Button Animation Triggers
$btnRDP.Add_MouseEnter({
	$btnRDP.FindResource("mouseEnterAnimation").Begin($btnRDP)
})

$btnRDP.Add_MouseLeave({
	$btnRDP.FindResource("mouseLeaveAnimation").Begin($btnRDP)
})

$btnReset.Add_MouseEnter({
	$btnReset.FindResource("mouseEnterAnimation").Begin($btnReset)
})

$btnReset.Add_MouseLeave({
	$btnReset.FindResource("mouseLeaveAnimation").Begin($btnReset)
})

$btnWebInterface.Add_MouseEnter({
	$btnWebInterface.FindResource("mouseEnterAnimation").Begin($btnWebInterface)
})

$btnWebInterface.Add_MouseLeave({
	$btnWebInterface.FindResource("mouseLeaveAnimation").Begin($btnWebInterface)
})

$btnShare.Add_MouseEnter({
	$btnShare.FindResource("mouseEnterAnimation").Begin($btnShare)
})

$btnShare.Add_MouseLeave({
	$btnShare.FindResource("mouseLeaveAnimation").Begin($btnShare)
})

$btnNone.Add_MouseEnter({
	$btnNone.FindResource("mouseEnterAnimation").Begin($btnNone)
})

$btnNone.Add_MouseLeave({
	$btnNone.FindResource("mouseLeaveAnimation").Begin($btnNone)
})

$btnPortScan.Add_MouseEnter({
	$btnPortScan.FindResource("mouseEnterAnimation").Begin($btnPortScan)
})

$btnPortScan.Add_MouseLeave({
	$btnPortScan.FindResource("mouseLeaveAnimation").Begin($btnPortScan)
})

# Export List in HTML format
$ExportToHTML.Add_Click({
	$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
	$saveFileDialog.Filter = "HTML files (*.html)|*.html|All files (*.*)|*.*"
	$saveFileDialog.FileName = "Network_Scan_Results"
	if ($saveFileDialog.ShowDialog() -eq "OK") {
		$path = $saveFileDialog.FileName
		try {
			# Create HTML content with header
			$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
	<title>Network Scan Results</title>
	<style>
		table, th, td { border: 1px solid black; border-collapse: collapse; padding: 5px; }
		th { background-color: #f2f2f2; }
		h1, p { margin: 0; padding: 0; }
		p { margin-bottom: 2px; }
		.info-block { margin-bottom: 20px; }
	</style>
</head>
<body>
	<h1>Network Scan Results</h1><br>
	<div class="info-block">
		<p><strong>External IP:</strong> $global:externalIP</p>
		<p><strong>Domain:</strong> $global:domain</p>
		<p><strong>Date/Time:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
		<p><strong>Total Devices:</strong> $global:totalCount</p>
	</div>
	<table>
		<tr>
			<th>MAC Address</th>
			<th>Vendor</th>
			<th>IP Address</th>
			<th>Host Name</th>
		</tr>
"@
			$listView.Items | ForEach-Object {
				$htmlContent += @"
		<tr>
			<td>$($_.MACaddress)</td>
			<td>$($_.Vendor)</td>
			<td>$($_.IPaddress)</td>
			<td>$($_.HostName.Replace(' (This Device)',''))</td>
		</tr>
"@
			}
			$htmlContent += @"
	</table>
</body>
</html>
"@

			# Write HTML to file
			[System.IO.File]::WriteAllText($path, $htmlContent)
			Show-Popup2 -Message 'Export to HTML completed successfully!' -Title 'Export:'
		}
		catch {
			Show-Popup2 -Message "Error during export: $_" -Title 'ERROR:'
		}
	}
})

# Export List in CSV format
$ExportToCSV.Add_Click({
	$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
	$saveFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
	$saveFileDialog.FileName = "Network_Scan_Results"
	if ($saveFileDialog.ShowDialog() -eq "OK") {
		$path = $saveFileDialog.FileName
		try {
			# CSV header
			$csvHeader = "MAC Address,Vendor,IP Address,Hostname"
			$csvContent = $listView.Items | ForEach-Object {
				"`r`n$($_.MACaddress.Replace(',','')),$($_.Vendor.Replace(',','')),$($_.IPaddress.Replace(',','')),$($_.HostName.Replace(' (This Device)','').Replace(',',''))"
			}
			[System.IO.File]::WriteAllLines($path, ($csvHeader + $csvContent))
			Show-Popup2 -Message 'Export to CSV completed successfully!' -Title 'Export:'
		}
		catch {
			Show-Popup2 -Message "Error during export: $_" -Title 'ERROR:'
		}
	}
})

# Export List in TXT format
$ExportToText.Add_Click({
	$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
	$saveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
	$saveFileDialog.FileName = "Network_Scan_Results"
	if ($saveFileDialog.ShowDialog() -eq "OK") {
		$path = $saveFileDialog.FileName
		try {
			# TXT header
			$textContent = @"
NETWORK SCAN RESULTS

EXTERNAL IP   : $global:externalIP
DOMAIN        : $global:domain
DATE/TIME     : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
TOTAL DEVICES : $global:totalCount

--------------------------------------
"@
			$textContent += $listView.Items | ForEach-Object {
@"

MAC      : $($_.MACaddress)
Vendor   : $($_.Vendor)
IP       : $($_.IPaddress)
Hostname : $($_.HostName.Replace(' (This Device)',''))
--------------------------------------
"@
			}
			[System.IO.File]::WriteAllText($path, $textContent)
			Show-Popup2 -Message 'Export to Text completed successfully!' -Title 'Export:'
		}
		catch {
			Show-Popup2 -Message "Error during export: $_" -Title 'ERROR:'
		}
	}
})

# Add listView column header click capture
$ListView.AddHandler(
	[System.Windows.Controls.GridViewColumnHeader]::ClickEvent,
	[System.Windows.RoutedEventHandler]$listViewSortColumn
)

# Find and assign Hostname column from listView to control width when scrollbar is present
$hostNameColumn = ($listView.View.Columns | Where-Object {$_.Header -eq "Host Name"})

$listView.Add_MouseDoubleClick({
	if($listView.SelectedItems.Count -gt 0){
		CheckConnectivity -selectedhost $listView.SelectedItems.IPaddress
		$selectedItem = $listView.SelectedItems[0]
		$pMAC.Text = "MAC: " + $selectedItem.MACaddress
		$pVendor.Text = "Vendor: " + $selectedItem.Vendor
		$pIP.Text = "IP: " + $selectedItem.IPaddress
		$pHost.Text = "Host: " + $selectedItem.HostName.Replace(' (This Device)','')
		$PopupCanvas.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [System.Windows.Controls.Canvas]::GetLeft($listView) + 10)
		$PopupCanvas.SetValue([System.Windows.Controls.Canvas]::TopProperty, [System.Windows.Controls.Canvas]::GetTop($listView) + 10)
		$PopupCanvas.Visibility = 'Visible'
	}
})

$listView.Add_MouseLeftButtonDown({
	$listView.SelectedItems.Clear()
})

# Single item pop-up context menu, IP Address to clipboard
$PopupContextCopyIP_Click = {
	if ($PopupCanvas.Visibility -eq 'Visible') {
		$ipText = $pIP.Text -replace 'IP: '
		Set-Clipboard -Value $ipText
		Show-Popup2 -Message 'IP Address copied to clipboard!' -Title 'Info:'
	} else {
		Show-Popup2 -Message 'No item available to copy IP Address from!' -Title 'Warning:'
	}
}
$PopupContextCopyIP.Add_Click($PopupContextCopyIP_Click)

# Single item pop-up context menu, Hostname to clipboard
$PopupContextCopyHostname_Click = {
	if ($PopupCanvas.Visibility -eq 'Visible') {
		$hostText = $pHost.Text -replace 'Host: '
		Set-Clipboard -Value $hostText
		Show-Popup2 -Message 'Hostname copied to clipboard!' -Title 'Info:'
	} else {
		Show-Popup2 -Message 'No item available to copy Hostname from!' -Title 'Warning:'
	}
}
$PopupContextCopyHostname.Add_Click($PopupContextCopyHostname_Click)

# Single item pop-up context menu, MAC Address to clipboard
$PopupContextCopyMAC_Click = {
	if ($PopupCanvas.Visibility -eq 'Visible') {
		$macText = $pMAC.Text -replace 'MAC: '
		Set-Clipboard -Value $macText
		Show-Popup2 -Message 'MAC Address copied to clipboard!' -Title 'Info:'
	} else {
		Show-Popup2 -Message 'No item available to copy MAC Address from!' -Title 'Warning:'
	}
}
$PopupContextCopyMAC.Add_Click($PopupContextCopyMAC_Click)

# Single item pop-up context menu, Vendor to clipboard
$PopupContextCopyVendor_Click = {
	if ($PopupCanvas.Visibility -eq 'Visible') {
		$vendorText = $pVendor.Text -replace 'Vendor: '
		Set-Clipboard -Value $vendorText
		Show-Popup2 -Message 'Vendor copied to clipboard!' -Title 'Info:'
	} else {
		Show-Popup2 -Message 'No item available to copy Vendor from!' -Title 'Warning:'
	}
}
$PopupContextCopyVendor.Add_Click($PopupContextCopyVendor_Click)

# Single item pop-up context menu, All details to clipboard
$PopupContextCopyAll_Click = {
	if ($PopupCanvas.Visibility -eq 'Visible') {
		$hostText = $pHost.Text -replace 'Host: '
		$ipText = $pIP.Text -replace 'IP: '
		$macText = $pMAC.Text -replace 'MAC: '
		$vendorText = $pVendor.Text -replace 'Vendor: '
		$details = "Host: $hostText`nIP: $ipText`nMAC: $macText`nVendor: $vendorText"
		Set-Clipboard -Value $details
		Show-Popup2 -Message 'All details copied to clipboard!' -Title 'Info:'
	} else {
		Show-Popup2 -Message 'No item available to copy details from!' -Title 'Warning:'
	}
}
$PopupContextCopyAll.Add_Click($PopupContextCopyAll_Click)

# Clear CTRL key value
$global:CtrlIsDown = $false

# KeyDown event handler
$Main.Add_KeyDown({
	if ($_.Key -eq 'LeftCtrl' -or $_.Key -eq 'RightCtrl') {
		$global:CtrlIsDown = $true
		if($Scan.IsEnabled){
			$scanButtonText.Text = 'Clear ARP cache'
			$scanAdminIcon.Visibility = 'Visible'
		}
	}
})

# KeyUp event handler
$Main.Add_KeyUp({
	if ($_.Key -eq 'LeftCtrl' -or $_.Key -eq 'RightCtrl') {
		$global:CtrlIsDown = $false
		if($Scan.IsEnabled){
			if ($global:gatewayPrefix -ne $originalGatewayPrefix) {
				$scanButtonText.Text = 'Custom Scan'
			} else {
				$scanButtonText.Text = 'Scan'
			}
			$scanAdminIcon.Visibility = 'Collapsed'
		}
	}
})

# Wait for background jobs to finish with progress tracking
function TrackProgress {
	$totalItems = $listView.Items.Count
	$completedItems = 0
	# Initialize to a value that will always differ from $completedItems on first check
	$previousCompletedItems = -1

	do {
		# Count items with both HostName and Vendor resolved
		$completedItems = ($listView.Items | Where-Object {
			$_.HostName -ne "Resolving..." -and
			$_.Vendor -ne "Identifying..."
		}).Count

		# Check if the number of completed items has changed
		if ($completedItems -ne $previousCompletedItems) {
			# Update UI with the new progress
			$completedPercentage = if ($totalItems -gt 0) {
				($completedItems / $totalItems) * 100
			} else {
				0
			}
			Update-Progress ([math]::Min(100, $completedPercentage)) 'Identifying Devices'

			# Refresh ListView to show changes
			$listView.Items.Refresh()
			Update-uiMain

			# Update the previous count for the next iteration
			$previousCompletedItems = $completedItems
		} else {
			# If no change, update the UI occasionally to show that the process is ongoing
			if ($completedItems -lt $totalItems) {
				Update-Progress ([math]::Min(100, $completedPercentage)) 'Identifying Devices'
			}
		}

		# Short sleep to not overload the system
		Start-Sleep -Milliseconds 5
	} while ($completedItems -lt $totalItems)
}

# Ensure clean ListView
if($listview.Items){
	$listview.Items.Clear()
}

$ExportContext.IsEnabled = $false

# Define Scan Button Actions
$btnScan.Add_MouseEnter({
	$btnScan.Background = '#EEEEEE'
})

$btnScan.Add_MouseLeave({
	$btnScan.Background = '#777777'
})

$Scan.Add_MouseEnter({
	$Scan.Background = '#EEEEEE'
})

$Scan.Add_MouseLeave({
	$Scan.Background = '#777777'
})

$Scan.Add_Click({
	if($PopupCanvas.Visibility -eq 'Visible') {
		$PopupCanvas.Visibility = 'Hidden'
	}
	if($PopupCanvas2.Visibility -eq 'Visible') {
		$PopupCanvas2.Visibility = 'Hidden'
	}
	# If CTRL key is held while clicking the Scan button, offer to clear ARP cache as Admin prior to Scan process
	if ($global:CtrlIsDown) {
		$Scan.IsEnabled = $false
		$osInfo = Get-CimInstance Win32_OperatingSystem
		if ($osInfo.Caption -match "Server") {
			Show-Popup2 -Message 'This option is not available for Windows Servers. Please clear your ARP Cache manually.' -Title 'Restricted Feature:'
		} else {
			try{
				Start-Process -Verb RunAs powershell -WindowStyle Minimized -ArgumentList '-Command "& {Remove-NetNeighbor -InterfaceAlias * -Confirm:$false}"'
				$listView.Items.Clear()
				$TotalListed.Text = ''
				Show-Popup2 -Message 'Cached peer list cleared...' -Title 'List Cleared:'
			}catch{
				Show-Popup2 -Message 'No action was taken...' -Title 'Process Aborted:'
			}
		}
		if ($global:gatewayPrefix -ne $originalGatewayPrefix) {
			$scanButtonText.Text = 'Custom Scan'
		} else {
			$scanButtonText.Text = 'Scan'
		}
		$scanAdminIcon.Visibility = 'Collapsed'
		$Scan.IsEnabled = $true
		$global:CtrlIsDown = $false
	} else {
		$Scan.IsEnabled = $false
		# Make ProgressBar visible, hide Button
		$Scan.Visibility = 'Collapsed'
		$Progress.Visibility = 'Visible'
		$Progress.Value = 0
		$BarText.Text = 'Initializing'
		$listView.Items.Clear()
		$TotalListed.Text = ''
		$global:totalCount = 0
		$ExportContext.IsEnabled = $false
		$hostNameColumn.Width = 284
		Update-uiMain
		Get-HostInfo -gateway $global:gateway -gatewayPrefix $global:gatewayPrefix -originalGatewayPrefix $originalGatewayPrefix
		$externalIPt.Text = "`- `[ External IP: $externalIP `]"
		$domainName.Text = "`- `[ Domain: $domain `]"
		Update-uiMain
		Scan-Subnet
		List-Machines
		processVendors
		processHostnames
		TrackProgress
		# Hide ProgressBar, show button
		$Progress.Visibility = 'Collapsed'
		$Scan.Visibility = 'Visible'
		$BarText.Text = ''
		$Scan.IsEnabled = $true
		$Progress.Value = 0
		if ($listView.Items.Count -eq 0) {
			$ExportContext.IsEnabled = $false
		} else {
			$ExportContext.IsEnabled = $true
			# Save the table as a text file
			$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
			$saveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
			$saveFileDialog.FileName = "IP_Scan_Results_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
			if ($saveFileDialog.ShowDialog() -eq "OK") {
				$path = $saveFileDialog.FileName
				$tableContent = "IP Address`tHost Name`tMAC Address`tVendor`n"
				$tableContent += "----------`t----------`t-----------`t------`n"
				foreach ($item in $listView.Items) {
					$tableContent += "$($item.IPaddress)`t$($item.HostName)`t$($item.MACaddress)`t$($item.Vendor)`n"
				}
				$tableContent | Out-File -FilePath $path -Encoding UTF8
				Show-Popup2 -Message "Scan results saved to: $path" -Title "Export Complete:"
			}
		}
		Update-uiMain
		$global:CtrlIsDown = $false
	}
})

# Show Window
$Main.ShowDialog() | out-null
