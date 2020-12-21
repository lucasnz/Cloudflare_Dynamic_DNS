function IsPrivateIPAddress {
    param (
        [string]$IPAddress = $Null,
        [string]$Type = $Null
    )

    #If IPAddress is not defined, then get one based on the interface address
    if ( -Not $IPAddress ) {
        if ( $Type -eq "A" ) {
            $IPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object -Property PrefixOrigin -ne "WellKnown")[0].IPAddress
        } elseif ( $Type -eq "AAAA" ) {
            $IPAddress = (Get-NetIPAddress -AddressFamily IPv6 | Where-Object -Property PrefixOrigin -ne "WellKnown")[0].IPAddress
        }
    }

    Write-Verbose "IsPrivateIPAddress: IP Address: $IPAddress, Type: $Type"

    try {
        $NetIPAddress = [Net.IPAddress]::Parse($IPAddress)
    }
    catch {
        Write-Error "ERROR: Not an IP Address: $IPAddress" -ErrorAction Stop
    }

    if ( -Not $Type ) {
        if ( $NetIPAddress.AddressFamily -eq "InterNetwork" ) { $Type = "A" }
        if ( $NetIPAddress.AddressFamily -eq "InterNetworkV6" ) { $Type = "AAAA" }
    }

    $PrivateIP = $False
    # if it's IPv6 check if it's link or site local 
    if ( $NetIPAddress.AddressFamily -eq "InterNetworkV6" -And $Type -eq "AAAA" ) {
        If ( $NetIPAddress.IsIPv6LinkLocal -Or $NetIPAddress.IsIPv6SiteLocal ) {
            $PrivateIP = $True
        }
    }
    elseif ( $NetIPAddress.AddressFamily -eq "InterNetwork" -And $Type -eq "A" ) {
        $BinaryIP = [String]::Join('.',
            $( $NetIPAddress.GetAddressBytes() | %{
            [Convert]::ToString($_, 2).PadLeft(8, '0') } ))

        #169.254. 0.0/16
        If ($BinaryIP -Match "^10101001.11111111") { $PrivateIP = $True }

        #192.168.0.0/16
        If ($BinaryIP -Match "^11000000.10101000") { $PrivateIP = $True }

        #172.16.0.0/12
        If ($BinaryIP -Match "^10101100.0001") { $PrivateIP = $True }

        #10.0.0.0/8
        If ($BinaryIP -Match "^00001010") { $PrivateIP = $True }
        
    }
    else {
        Write-Error "ERROR: IP Address: $IPAddress, Type: $Type" -ErrorAction Stop
    }


    return $PrivateIP
}

Export-ModuleMember -Function IsPrivateIPAddress