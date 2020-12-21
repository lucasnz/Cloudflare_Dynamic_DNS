[CmdletBinding()]
param (
    [string]$Zone = $(throw "-Zone is required."),
    [string]$Record = "$env:computername",
    [string]$Type = "A",
    [string]$Username = $(throw "-Username is required."),
    [string]$ApiKey = $( [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR( (Read-Host -asSecureString "Input password") )) ),
    [string]$IPAddress = $Null
)

Import-Module .\IsPrivateIPAddress.psm1

function CFDynDNS {
    #If IPAddress is not defined, then get one based on the interface address
    if ( -Not $IPAddress ) {
        if ( $Type -eq "A" ) {
            $IPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object -Property PrefixOrigin -ne "WellKnown")[0].IPAddress
        } elseif ( $Type -eq "AAAA" ) {
            $IPAddress = (Get-NetIPAddress -AddressFamily IPv6 | Where-Object -Property PrefixOrigin -ne "WellKnown")[0].IPAddress
        }
    }

    $ip_address = $IPAddress
    $record_type = $Type
    $record_name = $Record
    $zone_name = $Zone

    if ( IsPrivateIPAddress -IPAddress $ip_address -Type $record_type ) {
        Write-Verbose "CFDynDNS: Is Private IP: $ip_address, Type: $record_type"
        #IP Address is local so we need to look up our IP...
        $test_server = "ifconfig.co"
        $test_server_ip = (Resolve-DnsName -Name "$test_server" -Type "$type" -DnsOnly)[0].IPAddress

        if ($record_type -eq "AAAA") {
            $test_server_ip = "[$test_server_ip]"
        }
        try {
            $response = Invoke-WebRequest "https://$test_server_ip/ip" -Headers @{ host="$test_server" }
        }
        catch {
            Write-Error "ERROR: Cannot connect to test server: $test_server, test server IP: $test_server_ip" -ErrorAction Stop
        }
        
        $ip_address = ($response.Content).Trim()
    }

    Write-Verbose "CFDynDNS: IP Address: $ip_address, Type: $record_type"

    $headers = @{
        "X-Auth-Email"=$Username
        "X-Auth-Key"=$ApiKey
        "Content-Type"="application/json"
    }

    try {
        $response = Invoke-WebRequest -URI "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -Headers $headers
    }
    catch {
        Write-Error $_.Exception -ErrorAction Stop
    }

    if ($response.StatusCode -eq 200 ) {
        $zone_id = ($response.Content | ConvertFrom-Json).result.id
    } else {
        Write-Error "Error: status code: $response.StatusCode" -ErrorAction Stop
    }

    if (-Not $zone_id) {
        Write-Error "Error: cannot find zone: $zone_name" -ErrorAction Stop
    }

    try {
        $response = Invoke-WebRequest -URI "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$record_name.$zone_name" -Headers $headers
    }
    catch {
        Write-Error $_.Exception -ErrorAction Stop
    }

    $record_id = $null
    if ($response.StatusCode -eq 200 ) {
        $response_json = $response.Content | ConvertFrom-Json
        $record_id = $response_json.result.id
        $record_content = $response_json.result.content
    } else {
        Write-Error "Error: status code: $response.StatusCode" -ErrorAction Stop
    }

    $data = @{
        "type"="$record_type"
        "name"="$record_name.$zone_name"
        "content"="$ip_address"
        "ttl"="1"
    } | ConvertTo-Json

    #if we have an existing DNS record, then we can update it else, create it.
    if ($record_id) {
        Write-Verbose "CFDynDNS: Current record content: '$record_content', new IP Address: '$ip_address'"
        if ($record_content -eq $ip_address ) {
            Write-Verbose "CFDynDNS: Record matches. No action required..."
        }
        else {
            Write-Verbose "CFDynDNS: Updating record..."
            $response = Invoke-WebRequest -URI "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" -Headers $headers -Method "PUT" -Body $data
        }
    }
    else {
        Write-Verbose "CFDynDNS: Creating record..."
        $response = Invoke-WebRequest -URI "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" -Headers $headers -Method "POST" -Body $data
    }
}

CFDynDNS
