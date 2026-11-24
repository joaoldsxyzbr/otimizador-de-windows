# iniciar.ps1 - launcher sem instalacao, exclusivo do repositorio OtimizadorPC
# Execute no Windows PowerShell 5.1, como administrador para abrir o aplicativo.
[CmdletBinding()]
param(
    [ValidatePattern('^(main|desenvolvimento-v2|[a-fA-F0-9]{40})$')]
    [string]$Ref = 'main',
    [ValidateSet('seguro','balanceado','agressivo','essencial','gamer','notebook','privacidade','corporativo','recomendado')]
    [string]$Cli,
    [switch]$Simular,
    [switch]$SomenteValidar,
    # Fonte local para testes e uso offline; somente de uma copia confiavel.
    [string]$FonteLocal
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Este aplicativo requer Windows.' }
if ($Simular -and -not $Cli) { throw 'Use -Simular junto com -Cli.' }
if (-not $SomenteValidar) {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidade)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o Windows PowerShell como administrador e execute novamente.'
    }
}

$hostPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $hostPS -PathType Leaf)) { throw 'Windows PowerShell 5.1 nao encontrado.' }
$temporario = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-' + [guid]::NewGuid().ToString('N'))
if (-not $SomenteValidar) {
    $temporario = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) ('otimizadorpc-launch-' + [guid]::NewGuid().ToString('N'))
}
$repo = 'joaoldsxyzbr/otimizador-de-windows'
$arquivos = @(
    'otimizadorpc.ps1', 'montar-portatil.ps1',
    'src/modules/comum.ps1', 'src/modules/motor.ps1', 'src/modules/consertos.ps1',
    'src/modules/desinstalador.ps1', 'src/modules/sistema.ps1', 'src/modules/gui.ps1',
    'src/ui/principal.xaml', 'data/tweaks.json', 'data/aplicativos.json', 'data/uwp.json'
)
$tlsAnterior = [Net.ServicePointManager]::SecurityProtocol
$temporarioCriado = $false
try {
    if ($SomenteValidar) { New-Item -ItemType Directory -Path $temporario | Out-Null }
    else {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        $admin = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        $acl.SetOwner($admin)
        $heranca = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @($admin,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$heranca,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        }
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-3-4'),[Security.AccessControl.FileSystemRights]::ReadPermissions,$heranca,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        if (Test-Path -LiteralPath $temporario) { throw 'Pasta temporaria ja existe.' }
        [void][IO.Directory]::CreateDirectory($temporario,$acl)
    }
    $temporarioCriado = $true
    if ($FonteLocal) {
        $origem = (Get-Item -LiteralPath $FonteLocal).FullName
        $fonte = Join-Path $temporario 'fonte'
        New-Item -ItemType Directory -Path $fonte | Out-Null
        foreach ($rel in $arquivos) {
            $dest = Join-Path $fonte $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $origem $rel) -Destination $dest
        }
        Write-Host 'Usando fonte local explicitamente selecionada.'
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{ 'User-Agent' = 'OtimizadorPC-Launcher'; Accept = 'application/vnd.github+json' }
        if ($env:GITHUB_ACTIONS -eq 'true' -and $env:GH_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GH_TOKEN }
        try {
            $commit = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/commits/' + $Ref) -Headers $headers -TimeoutSec 30
            $sha = [string]$commit.sha
            $treeSha = [string]$commit.commit.tree.sha
            if ($sha -notmatch '^[0-9a-f]{40}$' -or $treeSha -notmatch '^[0-9a-f]{40}$') { throw 'Resposta de commit invalida.' }
            if ($Ref -match '^[0-9a-f]{40}$' -and $sha -ne $Ref) { throw 'Commit recebido diferente do solicitado.' }
            $arvore = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/git/trees/' + $treeSha + '?recursive=1') -Headers $headers -TimeoutSec 30
            if ($arvore.truncated -or $arvore.sha -ne $treeSha) { throw 'Arvore Git invalida ou incompleta.' }
        } catch {
            # Exclusivo da validacao de um commit ja presente no checkout.
            # Nao ignora divergencia de hash e nao executa o aplicativo.
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($status -notin @(403,429) -or -not $SomenteValidar -or $Ref -notmatch '^[0-9a-f]{40}$') { throw }
            $git = Get-Command git.exe -CommandType Application -ErrorAction Stop
            $checkout = $PSScriptRoot
            $sha = [string](& $git.Source -C $checkout rev-parse HEAD)
            if ($LASTEXITCODE -ne 0 -or $sha -ne $Ref) { throw 'API indisponivel e checkout nao corresponde ao commit solicitado.' }
            $linhas = @(& $git.Source -C $checkout ls-tree -r $sha)
            if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler a arvore Git local.' }
            $entradas = @()
            foreach ($linha in $linhas) {
                if ($linha -match '^([0-9]{6}) (blob) ([0-9a-f]{40})\t(.+)$') {
                    $entradas += [pscustomobject]@{ mode=$Matches[1]; type=$Matches[2]; sha=$Matches[3]; path=$Matches[4] }
                }
            }
            $arvore = [pscustomobject]@{ tree=$entradas }
            Write-Warning 'API retornou 403/429; usando arvore do checkout fixado para conferir os arquivos remotos. Aplicativo nao sera aberto.'
        }
        Write-Host ('Baixando OtimizadorPC: ' + $Ref + ' (' + $sha + ')')
        $fonte = Join-Path $temporario 'fonte'
        New-Item -ItemType Directory -Path $fonte | Out-Null
        # Le os bytes originais de cada blob Git, sem conversao de final de linha.
        foreach ($rel in $arquivos) {
            $entrada = @($arvore.tree | Where-Object { $_.path -ceq $rel -and $_.type -eq 'blob' -and $_.mode -eq '100644' })
            if ($entrada.Count -ne 1 -or $entrada[0].sha -notmatch '^[0-9a-f]{40}$') { throw ('Arquivo Git invalido: ' + $rel) }
            $dest = Join-Path $fonte $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            # Raw por commit evita uma chamada adicional a API por arquivo.
            # O hash do blob continua obrigatorio antes de executar.
            Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/' + $repo + '/' + $sha + '/' + $rel) -OutFile $dest -TimeoutSec 45
            $bytes = [IO.File]::ReadAllBytes($dest)
            $prefixo = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
            $hash = [Security.Cryptography.SHA1]::Create()
            try { $calculado = ([BitConverter]::ToString($hash.ComputeHash([byte[]]($prefixo + $bytes)))).Replace('-','').ToLowerInvariant() }
            finally { $hash.Dispose() }
            if ($calculado -ne $entrada[0].sha) { throw ('Integridade Git divergente: ' + $rel) }
        }
        Write-Host 'Arquivos conferidos com o commit do GitHub.'
    }

    $montador = Join-Path $fonte 'montar-portatil.ps1'
    & $hostPS -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $montador
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao montar a versao portatil.' }
    $portatil = Join-Path $fonte 'dist\otimizadorpc-portatil.ps1'
    $erros = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($portatil, [ref]$null, [ref]$erros)
    if (-not (Test-Path -LiteralPath $portatil -PathType Leaf) -or @($erros).Count -gt 0) { throw 'Versao portatil invalida.' }
    if ($SomenteValidar) { Write-Host 'Launcher validado; aplicativo nao executado.'; return }

    Write-Host 'Abrindo OtimizadorPC...'
    $argsApp = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$portatil)
    if ($Cli) { $argsApp += @('-Cli',$Cli) }
    if ($Simular) { $argsApp += '-Simular' }
    & $hostPS @argsApp
    if ($LASTEXITCODE -ne 0) { throw ('OtimizadorPC terminou com codigo ' + $LASTEXITCODE) }
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $tlsAnterior
    if ($temporarioCriado -and (Test-Path -LiteralPath $temporario)) {
        try { Remove-Item -LiteralPath $temporario -Recurse -Force -ErrorAction Stop }
        catch { Write-Warning ('Nao foi possivel limpar a pasta temporaria: ' + $temporario) }
    }
}
