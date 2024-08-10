$ping = [System.Net.NetworkInformation.Ping]::new();

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Linq;

public class IPRange {
        private uint start;
        private uint end;
        public IPRange(string range) {
                int slash = range.IndexOf('/');
                string ap;
                int pp = 32;
                if (slash != -1) {
                        ap = range.Remove(slash);
                        pp = int.Parse(range.Substring(slash + 1));
                }
                else {
                        ap = range;
                }
                uint address = BitConverter.ToUInt32(System.Net.IPAddress.Parse(ap).GetAddressBytes().Reverse().ToArray(), 0);
                if (pp == 32) {
                        start = end = address;
                }
                else {
                        uint rx = 1u << (32 - pp);
                        rx--;
                        start = address & (~rx);
                        end = start | (rx);
                }
        }
        public IPAddress Start {
                get {
                        return new IPAddress(BitConverter.GetBytes(start).Reverse().ToArray());
                }
        }
        public IPAddress End {
                get {
                        return new IPAddress(BitConverter.GetBytes(end).Reverse().ToArray());
                }
        }
        public uint Length {
                get {
                        return end - start + 1;
                }
        }
        public IPAddress this[long index] {
                get {
                        if (index >= Length || index < 0) { throw new IndexOutOfRangeException(); }
                        return new IPAddress(BitConverter.GetBytes((uint)(start + index)).Reverse().ToArray());
                }
        }
}
"@;

if ($global:ips -eq $null) {
$global:ips = [IPRange[]]@(
        "1.0.0.0/24",
        "1.1.1.1/24",
        "23.227.37.0/24",
        "23.227.38.0/23",
        "23.227.60.0/24",
        "64.68.192.0/24"
        "66.235.200.0/24",
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/12",
        "172.64.0.0/13",
        "131.0.72.0/22"
);
}
function Measure-HttpRequest {
        param($Proxy = $null, $Uri, [string]$Method = "GET", [double]$Timeout = 5000);
        $hch = [System.Net.Http.HttpClientHandler]::new();
        $hch.AllowAutoRedirect = $false;
        $hch.Proxy = [System.Net.WebProxy]::new($Proxy);
        $hc = [System.Net.Http.HttpClient]::new($hch);
        $hc.Timeout = [System.TimeSpan]::FromMilliseconds($Timeout);
        $hrm = [System.Net.Http.HttpRequestMessage]::new();
        $hrm.RequestUri = $Uri;
        $hrm.Method = $Method;
        $hrm.Version = "3.0";
        $x = $hc.SendAsync($hrm);
        $failed = $false;
        $time = Measure-Command { try { $x.Wait();  } catch [System.Exception] { $failed = $true; $exception = $_.Exception; } }
        if ($failed) { return @{ Success = $false; Status = 0; Reason = $exception; Time = $time; }; }
        $result = $x.Result;
        return @{ Success = $result.IsSuccessStatusCode; Time = $time; Status = [int]$result.StatusCode; Reason = $result.ReasonPhrase; Version = $result.Version; Headers = $result.Headers; Response = $result.Content.ReadAsStringAsync().Result; };
}

$script:total = 0;

function Test-IcmpEcho {
        param($Destination, $Timeout)
        return $ping.Send($Destination, $Timeout)
}

function Get-RandomAddress {
        if ($randomMode -eq 0) {
                [int]$n=(Get-Random -Minimum 0 -Maximum $total);
                foreach ($range in $ips) {
                        if ($n -lt $range.Length) {
                                return $range[$n];
                        }
                        $n -= $range.Length;
                }
        }
        elseif ($randomMode -eq 1) {
                [int]$x=(Get-Random -Minimum 0 -Maximum $ips.Length);
                [int]$y=(Get-Random -Minimum 0 -Maximum $ips[$x].Length);
                return $ips[$x][$y];
        }
}
if ($global:sampleCount -eq $null) { $global:sampleCount = 12; }
if ($global:maxFailure -eq $null) { $global:maxFailure = 3; }
if ($global:pingTimeout -eq $null) { $global:pingTimeout = 1000; }
if ($global:httpTimeout -eq $null) { $global:httpTimeout = 1500; }
if ($global:randomMode -eq $null) { $global:randomMode = 0; }
if ($global:autoFlush -eq $null) { $global:autoFlush = $true; }
if ($global:ipQueryUri -eq $null) { $global:ipQueryUri = "https://cq-api.racshs.eu.org/ip"; }

function Write-Result {
        param ([string]$Content, [string]$Control = $null, [switch]$NoNewline);
        if ($Control -ne $null -and $Control -ne "") { Write-Host ([Char]27 + $Control + $Content) -NoNewline }
        else { Write-Host $Content -NoNewline }
        [Console]::Out.Flush()
        if (-not $NoNewline) { Write-Host; }
#       if ($log -ne $null) {
#               $log.Write($Content);
#               if (-not $NoNewline) { $log.WriteLine(); if ($autoFlush) { $log.Flush(); } }
#       }
}
function Write-TestLog {
        param ([string]$Content);
        if ($log -ne $null) {
                $log.WriteLine($Content);
                $log.Flush();
        }
}
function Get-ControlSequence {
        param ([double]$Value, [double]$ThrL = 120, [double]$ThrM = 225, [double]$ThrH = 400, [double]$EMax = 1000, [double]$EMin = 60);
        if ($Value -lt $EMin) { return "[38;2;0;255;255m"; }
        elseif ($Value -lt $ThrL) { return "[38;2;0;255;$(255 - [int](255 * ($Value - $EMin) / ($ThrL - $EMin)))m"; }
        elseif ($Value -lt $ThrM) { return "[38;2;$([int](255 * ($Value - $ThrL) / ($ThrM - $ThrL)));255;0m"; }
        elseif ($Value -lt $ThrH) { return "[38;2;255;$(255 - [int](255 * ($Value - $ThrM) / ($ThrH - $ThrM)));$([int](255 * ($Value - $ThrM) / ($ThrH - $ThrM)))m"; }
        elseif ($Value -lt $EMax) { return "[38;2;255;0;$(255 - [int](255 * ($Value - $ThrH) / ($EMax - $ThrH)))m"; }
        else { return "[38;2;255;0;0m"; }
}
function Get-Average {
        param ([int[]]$Values, [int]$Count);
        $result = 0.0;
        for ($i = 0; $i -lt $Count; $i++) { $result += $Values[$i]; }
        return $result / $Count;
}
function Get-Deviation {
        param ([int[]]$Values, [double]$Avg, [int]$Count);
        $result = 0.0;
        for ($i = 0; $i -lt $Count; $i++) {
                $result += [Math]::Pow($Values[$i] - $Avg, 2);
        }
        return $result / $Count;
}
function Get-PingScore {
        param ([double]$RTT, [double]$SuccessRate, [double]$Deviation);
        $result = ($SuccessRate / 2) + ((($pingTimeout - $RTT) / $pingTimeout) / 2) - [Math]::log($Deviation + 1, $pingTimeout);
        if ($result -lt 0) { return 0; }
        return $result;
}
function Get-HttpScore {
        param ([double]$time);
        return ($httpTimeout - $time) / $httpTimeout;
}
function Start-Test {
        param ([string]$LogFile = "")
        try {
                if ($LogFile.Length -gt 0) {
                        Write-Result -Control "[38;2;0;255;0m" "Logging to $LogFile.";
                        Set-Variable -Scope Script -Name log -Value ([System.IO.StreamWriter]::new([System.IO.File]::Open($LogFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)));
                }
                $total = 0;
                foreach ($range in $ips) {
                        $total += $range.Length;
                }
                Write-TestLog "** Server test started at $((Get-Date).ToString('R')), with $total IP addresses in total.";
                Write-Result "Checking IP... " -NoNewLine;
                $response = Measure-HttpRequest -Uri $ipQueryUri -Timeout 5000;
                if (-not $response.Success) {
                        Write-Result -Control "[38;2;255;0;0m" "First attempt failed: $($response.Reason.Message).";
                        Write-Result "Checking IP... " -NoNewLine;
                        $response = Measure-HttpRequest -Uri $ipQueryUri -Timeout 5000;
                        if (-not $response.Success) {
                                Write-Result -Control "[38;2;255;0;0m" "Second attempt failed: $($response.Reason.Message).";
                                Write-Result "Checking IP... " -NoNewLine;
                                $response = Measure-HttpRequest -Uri $ipQueryUri -Timeout 5000;
                                if (-not $response.Success) {
                                        Write-Result -Control "[38;2;255;0;0m" "Thrid attempt failed: $($response.Reason.Message).";
                                        Write-Result -Control "[38;2;255;0;0m" "Give up.";
                                        Write-TestLog "!! Client IP address UNKNOWN.";
                                }
                                else { Write-Result -Control "[38;2;0;0;255m" $response.Response; Write-TestLog "** Client IP address $($response.Response)."; }
                        }
                        else { Write-Result -Control "[38;2;0;0;255m" $response.Response; Write-TestLog "** Client IP address $($response.Response)."; }
                }
                else { Write-Result -Control "[38;2;0;0;255m" $response.Response; Write-TestLog "** Client IP address $($response.Response)."; }
                Write-Result "Total $total IP Addresses." -Control "[38;2;0;255;0m";
                while($true) {
                        $ProgressPreference = 'SilentlyContinue';
                        [Net.IPAddress]$t = Get-RandomAddress;
                        Write-Result -NoNewline "$t`t" -Control "[38;2;255;255;255m";
                        $success = $false
                        $retry = $maxFailure;
                        $skip = $false;
                        $results = @(0) * $sampleCount
                        $successCount = 0
                        for ($i = 0; $i -lt $sampleCount; $i++) {
                                if ($skip) { Write-Result -Control "[38;2;128;128;128m" '-' -NoNewline; }
                                else {
                                        $r = Test-IcmpEcho -Timeout $pingTimeout -Destination $t;
                                        if ($r.Status -eq "Success") {
                                                $success = $true;
                                                $results[$successCount] = $r.RoundtripTime;
                                                $successCount++;
                                                # Write-Result -NoNewline "$($r.Status) " -Control "[38;2;0;255;0m";
                                                Write-Result -NoNewline "$($r.RoundtripTime)" -Control (Get-ControlSequence $r.RoundtripTime);
                                        }
                                        else {
                                                Write-Result -NoNewline "*" -Control "[38;2;255;0;0m";
                                                $fails = $r.Status;
                                                if (--$retry -eq 0) { $skip = $true; }
                                        }
                                }
                                if ($i -lt $sampleCount - 1) { Write-Result "`t" -NoNewline; }
                        }
                        if ($success) {
                                Write-Result -NoNewline "`tSuccess`t" -Control "[38;2;0;255;0m";
                                $avg = Get-Average -Values $results -Count $successCount
                                $dev = Get-Deviation -Values $results -Count $successCount -Avg $avg;
                                $rate = $successCount / $sampleCount;
                                $psc = Get-PingScore -RTT $avg -Deviation $dev -SuccessRate $rate;
                                $response = Measure-HttpRequest -Uri ("http://" + $t.ToString()) -Timeout $httpTimeout;
                                if ($response.Status -ne 0) {
                                        $location = "???"
                                        try {
                                                $location = $response.Headers.GetValues("CF-Ray").Substring(17)
                                                Write-Result $location -NoNewLine -Control "[38;2;0;0;255m";
                                        }
                                        catch {
                                                Write-Result "N/A" -NoNewLine -Control "[38;2;255;255;0m";
                                        }
                                        Write-Result " - " -NoNewLine;
                                        $httpTime = $response.Time.TotalMilliseconds;
                                        $hsc = Get-HttpScore $httpTime;
                                        Write-Result -NoNewline $httpTime -Control (Get-ControlSequence $httpTime -EMin 100 -EMax 2000 -ThrL 300 -ThrM 500 -ThrH 1000);
                                        $logstr = ([string]::Format("Server {0}`n`tPing score={1:.000} rate={2:0.00}% avg={3:0.00} dev={4:0.00} error={5}`n`tHttp score={6:.000} time={7} location={8} error={9}", $t.ToString(), $psc, $rate * 100, $avg, $dev, "NoError", $hsc, $httpTime, $location, "NoError"));
                                        Write-TestLog $logstr;
                                }
                                else {
                                        $initex = $response.Reason;
                                        while ($initex.InnerException -ne $null) { $initex = $initex.InnerException; }
                                        Write-Result -NoNewline "???" -Control "[38;2;255;0;0m";
                                        Write-Result -NoNewline " - ";
                                        $errName = "Unknown"
                                        if ($initex -eq $null) { Write-Result -NoNewline -Control "[38;2;255;0;0m" "UnknownError" -BackgroundColor White; }
                                        elseif ($initex.GetType() -eq [System.Threading.Tasks.TaskCanceledException]) { Write-Result -NoNewline -Control "[38;2;255;0;0m" "TimedOut"; $errName = "TimedOut"; }
                                        elseif ($initex.GetType() -eq [System.Net.Sockets.SocketException]) { Write-Result -NoNewline -Control "[38;2;255;0;0m" $initex.SocketErrorCode; $errName = $initex.SocketErrorCode; } else { Write-Result -NoNewline $initex.Message -Control "[38;2;255;255;0m"; $errName = $initex.Message; }
                                        $logstr = ([string]::Format("Server {0}`n`tPing score={1:.000} rate={2:0.00}% avg={3:0.00} dev={4:0.00} error={5}`n`tHttp score=-1 time={7} location={8} error={9}", $t, $psc, $rate * 100, $avg, $dev, "NoError", 0, $httpTime, "???", $errName));
                                        Write-TestLog $logstr;
                                }
                        }
                        else {
                                Write-Result -NoNewline "`t$($r.Status) " -Control "[38;2;255;0;0m";
                                Write-TestLog "Server $t`n`tPing score=-1 rate=0.00% avg=-1 dev=-1 error=$($r.Status)`n`tHttp score=-1 location=N/A error=Skipped"
                        }
                        Write-Result;
                }
        }
        catch {
                Write-Result ("*** FATAL EXCEPTION *** " + $_.Exception.Message) -Control "[38;2;255;0;0m";
                Write-TestLog ":( Disaster happened: $($_.Exception.Message)";
                Write-Result "Requesting stop...";
        }
        finally {
                Write-Result "*** STOP REQUESTED ***";
                if ($log -ne $null) {
                        Write-Host "Closing Log File...";
                        $log.Close();
                        $log.Dispose();
                        Set-Variable -Scope Script -Name log -Value $null;
                }
                Write-Host "Exiting...";
        }
}
