 <#
 .SYNOPSIS
     检查并一键剥离指定文件或目录中 JSON 文件的 UTF-8 BOM。
 .PARAMETER Path
     文件或目录路径。
 #>
 param(
     [Parameter(Mandatory = $true)]
     [string]$Path
 )
 
 if (-not (Test-Path -LiteralPath $Path)) {
     Write-Error "路径不存在: $Path"
     exit 1
 }
 
 $files = @()
 if ((Get-Item -LiteralPath $Path) -is [System.IO.DirectoryInfo]) {
     $files = Get-ChildItem -LiteralPath $Path -Filter "*.json" -Recurse -File
 } else {
     $files = @(Get-Item -LiteralPath $Path)
 }
 
 foreach ($f in $files) {
     $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
     if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
         $noBom = $bytes[3..($bytes.Length - 1)]
         [System.IO.File]::WriteAllBytes($f.FullName, $noBom)
         Write-Host "[BOM 已剥离] $($f.FullName) ($($bytes.Length) -> $($noBom.Length) bytes)" -ForegroundColor Green
     } else {
         Write-Host "[正常无BOM] $($f.FullName)" -ForegroundColor DarkGray
     }
 }
