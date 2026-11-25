# Launcher de distribuicao oficial. Sem instalacao e sem gravacao de arquivo.
# Diagnostico (somente leitura, sem elevacao):
#   irm https://raw.githubusercontent.com/joaoldsxyzbr/otimizador-de-windows/main/abrir.ps1 | iex
# Autorizado (alteracoes por operacao; pede confirmacao no UAC):
#   $AutorizarOtimizador = $true; irm https://raw.githubusercontent.com/joaoldsxyzbr/otimizador-de-windows/main/abrir.ps1 | iex
& {
    $ErrorActionPreference = 'Stop'
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Use Windows PowerShell 5.1.'
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Use Windows PowerShell em modo STA.'
    }
    $autorizar = $false
    $variavelAutorizacao = Get-Variable -Name 'AutorizarOtimizador' -ErrorAction SilentlyContinue
    if ($null -ne $variavelAutorizacao -and $variavelAutorizacao.Value -eq $true) { $autorizar = $true }
    $administrador = $false
    try {
        $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
        try { $administrador = (New-Object Security.Principal.WindowsPrincipal($identidade)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } finally { $identidade.Dispose() }
    } catch { $administrador = $false }
    if ($autorizar -and -not $administrador) {
        $comandoElevado = '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $AutorizarOtimizador = $true; irm https://raw.githubusercontent.com/joaoldsxyzbr/otimizador-de-windows/main/abrir.ps1 | iex'
        $codificado = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($comandoElevado))
        Write-Host 'Solicitando elevacao para abrir autorizado. Confirme o prompt do Windows.'
        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        try {
            Start-Process -FilePath $powershellExe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-EncodedCommand',$codificado) -Verb RunAs
        } catch {
            throw 'Elevacao recusada ou indisponivel. Nenhum aplicativo foi executado.'
        }
        return
    }
    $web = New-Object System.Net.WebClient
    try {
        $tag = $web.DownloadString('https://raw.githubusercontent.com/joaoldsxyzbr/otimizador-de-windows/main/versao-atual.txt').Trim()
        if ($tag -notmatch '\Av\d+\.\d+\.\d+(?:-(?:rc|beta|alpha|preview)\.\d+)?\z') {
            throw 'Versao publicada invalida. Nenhum aplicativo foi executado.'
        }
        $base = 'https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/' + $tag
        $hashText = $web.DownloadString($base + '/otimizadorpc.ps1.sha256').TrimStart([char]0xFEFF).Trim()
        if ($hashText -notmatch '\A([a-fA-F0-9]{64})\s+\*?otimizadorpc\.ps1\z') {
            throw 'Arquivo SHA256 invalido. Nenhum aplicativo foi executado.'
        }
        $esperado = $Matches[1]
        $bytes = $web.DownloadData($base + '/otimizadorpc.ps1')
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $real = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
        finally { $sha.Dispose() }
        if ($real -ine $esperado) { throw 'SHA256 divergente. Nenhum aplicativo foi executado.' }
        $codigo = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes).TrimStart([char]0xFEFF)
    } finally { $web.Dispose() }
    if ($autorizar) {
        Write-Host ('OtimizadorPC ' + $tag + ' - SHA256 conferido. Abrindo autorizado; cada operacao verifica seu contexto.')
        & ([scriptblock]::Create($codigo)) -Pessoal
    } else {
        Write-Host ('OtimizadorPC ' + $tag + ' - SHA256 conferido. Somente diagnostico.')
        & ([scriptblock]::Create($codigo)) -Diagnostico
    }
}
