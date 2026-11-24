# ============================================================
#  otimizadorpc.ps1 - app de otimizacao do windows do joao
#  janela nativa wpf (estilo winutil do chris titus), win10 e win11
#  como rodar: clique duas vezes em rodar-como-admin.bat
#  modo cli (sem janela): .\otimizadorpc.ps1 -Cli balanceado [-Simular]
# ============================================================

param(
    # modo cli: aplica um preset (seguro/balanceado/agressivo) sem abrir janela
    [string]$Cli,
    # junto com -Cli: so descreve o que faria, nao altera nada
    [switch]$Pessoal,
    [switch]$Diagnostico,
    [switch]$Simular
)

# ---- auto-elevacao para administrador ----
# Nenhuma elevacao automatica. Sem admin, abre somente diagnostico.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use Windows PowerShell 5.1.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Use Windows PowerShell em modo STA.' }
$ErrorActionPreference = 'Continue'

# ---- assemblies do wpf ----
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
} catch {
    [System.Windows.MessageBox]::Show('Nao foi possivel carregar o WPF: ' + $_.Exception.Message, 'OtimizadorPC')
    exit 1
}

# ---- modulos do app ----
$pastaModulos = Join-Path $PSScriptRoot 'src\modules'
. (Join-Path $pastaModulos 'comum.ps1')
. (Join-Path $pastaModulos 'motor.ps1')
. (Join-Path $pastaModulos 'consertos.ps1')
. (Join-Path $pastaModulos 'desinstalador.ps1')
. (Join-Path $pastaModulos 'sistema.ps1')
. (Join-Path $pastaModulos 'gui.ps1')

$travaInstancia = $null
try {
    Inicializar-ModoOtimizador -Pessoal:$Pessoal -Diagnostico:($Diagnostico -or ($Cli -and $Simular))
    if ($Cli -and -not $Simular -and $global:ModoProtegido) { throw 'Preset real exige -Pessoal, administrador e nenhum sinal de gerenciamento. Use -Cli essencial -Simular.' }
    if (-not $global:ModoProtegido) {
        Garantir-Pastas
        $travaInstancia = Obter-TravaInstancia
    }

# ---- catalogos ----
try {
    $global:CatalogoTweaks = Ler-JSON (Join-Path $global:PastaDados 'tweaks.json')
    $global:CatalogoApps   = Ler-JSON (Join-Path $global:PastaDados 'aplicativos.json')
    $global:CatalogoUwp    = Ler-JSON (Join-Path $global:PastaDados 'uwp.json')
} catch {
    $msg = 'Falha ao ler os catalogos em \data: ' + $_.Exception.Message
    if ($Cli) { Write-Host $msg -ForegroundColor Red } else {
        [System.Windows.MessageBox]::Show($msg, 'OtimizadorPC')
    }
    exit 1
}

# ---- tweaks custom (arquivos .reg na pasta custom\ ao lado do app) ----
$tweaksCustom = if ($global:ModoProtegido) { @() } else { @(Carregar-TweaksCustom) }
$global:CatalogoTweaks.tweaks = @($global:CatalogoTweaks.tweaks) + $tweaksCustom

# ---- modo cli: aplica o preset e sai, sem carregar a janela ----
if ($Cli) {
    # no cli o log vai pro console e pro arquivo; as funcoes de status sao
    # ui-safe (checam o dicionario $global:UI), entao so o log precisa de override
    function global:Log {
        param([string]$Mensagem, [switch]$Erro)
        $prefixo = ''
        if ($Erro) {
            $prefixo = '[ERRO] '
            $global:ErrosSessao++
        }
        $linha = ("{0}[{1}] {2}" -f $prefixo, (Get-Date -Format 'HH:mm:ss'), $Mensagem)
        Write-Host $linha
        if (-not $global:ModoProtegido) { try { Add-Content -LiteralPath $global:ArquivoLog -Value $linha -Encoding UTF8 -ErrorAction Stop } catch { } }
    }

    Log ('otimizadorpc modo cli - ' + (Nome-Windows))
    if (-not $global:ModoProtegido) { Log ('log desta execucao: ' + $global:ArquivoLog) } else { Log 'Diagnostico/simulacao: sem log persistente.' }
    if ($global:AmbienteTrabalho.Count -gt 0) {
        Log 'AMBIENTE: este pc parece gerenciado pela empresa; revise o log com atencao.'
    }
    $ok = Aplicar-Preset -Nivel $Cli -Simular:$Simular
    if (-not $global:ModoProtegido) { Log ('log completo salvo em: ' + $global:ArquivoLog) }
    if ($ok) { exit 0 } else { exit 1 }
}

# ---- janela ----
$xamlCaminho = Join-Path $PSScriptRoot 'src\ui\principal.xaml'
try {
    $xamlTexto = Get-Content -Path $xamlCaminho -Raw -Encoding UTF8
    Ler-TemaOtimizador
    $xamlTexto = Converter-TemaXaml $xamlTexto $global:TemaOtimizador
    $leitor = New-Object System.IO.StringReader($xamlTexto)
    $leitorXml = [System.Xml.XmlReader]::Create($leitor)
    $global:Janela = [Windows.Markup.XamlReader]::Load($leitorXml)
    $leitorXml.Close()
    $leitor.Close()
} catch {
    $msg = 'Falha ao montar a janela (XAML): ' + $_.Exception.Message
    [System.Windows.MessageBox]::Show($msg, 'OtimizadorPC') | Out-Null
    exit 1
}

# ---- liga todos os controles nomeados ----
$controles = @(
    'PontoStatus', 'StatusTexto', 'BarraProgresso', 'LogBox',
    'BotaoNavInicio', 'BotaoNavAjustes', 'BotaoNavDebloat', 'BotaoNavDesinstalar', 'BotaoNavInstalar',
    'BotaoNavConfig', 'BotaoNavAtualizacoes', 'BotaoNavManutencao', 'BotaoNavDesfazer',
    'InfoHost', 'InfoSo', 'InfoCpu', 'InfoGpu', 'InfoRam', 'InfoDisco', 'InfoUptime', 'InfoRestore', 'InfoAmbiente', 'InfoDiagnostico',
    'BotaoCriarRestore', 'BotaoInventario', 'BotaoCarga', 'BotaoDiagnosticoAvancado', 'BotaoMonitor', 'BotaoMedicoes', 'BotaoVerificarRelease',
    'ListaAjustes', 'ChkPontoRestore', 'ChkSimularAjustes', 'BotaoPresetSeguro', 'BotaoPresetBalanceado', 'BotaoPresetAgressivo', 'BotaoPerfilEssencial', 'BotaoPerfilGamer', 'BotaoPerfilNotebook', 'BotaoPerfilPrivacidade', 'BotaoPerfilCorporativo', 'BotaoPerfilRecomendado', 'BotaoAplicarAjustes', 'FiltroAjustes', 'BotaoExportarPlano', 'BotaoImportarPlano',
    'ListaUwp', 'ChkPontoRestoreUwp', 'BotaoRemoverUwp', 'FiltroUwp',
    'ListaProgramas', 'FiltroDesinstalar', 'CategoriaDesinstalar', 'OrdemDesinstalar', 'BotaoDetalhesPrograma', 'InfoProgramas', 'DetalhePrograma', 'BotaoAtualizarProgramas', 'ChkPontoRestoreDesinstalar', 'BotaoDesinstalarProg', 'BotaoVarrerRastros', 'RotuloRastros', 'BotaoMarcarRastros', 'BotaoDesmarcarRastros', 'InfoMarcadosRastros', 'BotaoApagarRastros', 'ListaRastros',
    'ListaApps', 'BotaoInstalarApps', 'BotaoAtualizarSelecionados', 'BotaoAtualizarTudo', 'BotaoMarcarPadroes', 'FiltroApps',
    'ListaRecursos', 'BotaoInstalarRecursos', 'BotaoFixUpdate', 'BotaoFixRede', 'BotaoFixIntegridade', 'BotaoFixWinget', 'BotaoTema', 'PainelLegado',
    'ChkBloquearDrivers', 'ChkAdiarRecursos', 'InfoPoliticasUpdate', 'BotaoAplicarAtualizacoes', 'BotaoBuscarAtualizacoes', 'BotaoResetUpdate2',
    'BotaoLimparTemp', 'BotaoLimpezaDisco', 'BotaoAnalisarComponentes', 'BotaoDiagnosticarIntegridade', 'BotaoConsultarEnergia', 'BotaoLimpezaDism', 'BotaoVerificarIntegridade', 'BotaoVerificarDisco',
    'BotaoRecuperarIcones', 'BotaoLimparDns', 'BotaoSincronizarHora', 'BotaoBackupDrivers', 'BotaoAnalisarArmazenamento',
    'ListaDesfazer', 'BotaoDesfazer', 'BotaoDesfazerUma', 'BotaoConfirmarManual', 'BotaoAtualizarListaSessoes', 'BotaoDetalhesSessao'
)
foreach ($nome in $controles) {
    $global:UI[$nome] = $global:Janela.FindName($nome)
    if ($null -eq $global:UI[$nome]) {
        [System.Windows.MessageBox]::Show('Controle nao encontrado no XAML: ' + $nome, 'OtimizadorPC') | Out-Null
        exit 1
    }
}

# ---- monta a interface e mostra ----
Ligar-Tudo

Log ('otimizadorpc iniciado - ' + (Nome-Windows))
Log ('modo: ' + $global:ModoOtimizador)
if ($global:ModoProtegido) {
    Log 'Somente diagnostico local. Sem elevacao automatica, alteracoes, exportacao ou log persistente.'
    foreach ($a in $global:AmbienteTrabalho) { Log ('  - ' + $a) }
} else {
    Log 'Nenhum sinal consultado de gerenciamento; isso nao prova que o PC seja pessoal.'
    Log 'Revise ajustes e pontos de restauracao antes de aplicar.'
}
$global:Janela.Title = ('OtimizadorPC ' + $global:VersaoOtimizador + ' - ' + (Nome-Windows) + ' - ' + $global:ModoOtimizador)
[void]$global:Janela.ShowDialog()

} finally {
    if ($null -ne $travaInstancia) { $travaInstancia.Dispose() }
}
