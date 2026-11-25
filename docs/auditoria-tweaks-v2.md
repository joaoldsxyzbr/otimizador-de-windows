# Auditoria inicial do catalogo V2 (F5, issue #2)

Base: `0dcec6b8077bf918b6162b05e5653b8c3c37a0e2`, 42 IDs. Revisao estatica do repositorio, nao certificacao pela Microsoft nem benchmark. As fontes oficiais por mecanismo, compatibilidade real por build/edicao, politicas efetivas e validacao em Windows cliente continuam pendentes. Nenhuma linha implica seguranca universal.

Nesta entrega: 8 ajustes contextuais passam a selecao manual; removidos o alinhamento de barra do ajuste de ocultacao de icones e a escrita integral de UserPreferencesMask. IDs mantidos; journals anteriores nao devem ser reinterpretados segundo catalogo novo.

| ID | Decisao preliminar | Motivo / validacao necessaria | Escopo de escrita |
| --- | --- | --- | --- |
| `telemetria` | Reformular | Mistura preferencias de usuario e variavel de maquina; separar fala, publicidade e telemetria do PowerShell; sem ganho comprovado. | HKCU, HKLM |
| `historico-atividades` | Reformular | Politicas de Timeline dependem de build; nao sobrescrever politica externa. | HKLM |
| `apps-sugeridos` | Reformular | Politicas de conteudo dependem da edicao; preferir configuracoes nativas. | HKLM, HKCU |
| `delivery-optimization` | Reformular | Desligar P2P pode aumentar trafego WAN; nao recomendar genericamente. | HKLM |
| `wpbt` | Reformular | Pode impedir software OEM legitimo; retirar linguagem de recomendacao geral. | HKLM |
| `device-metadata` | Reformular | Pode impedir utilitarios de hardware; sem beneficio geral. | HKLM |
| `bing-no-menu-iniciar` | Reformular | Valores de pesquisa dependem da build; validar efeito e politica. | HKCU |
| `localizacao` | Reformular | Servico e sensores podem afetar mapas e aplicativos; preferir consentimento nativo. | servico, HKLM |
| `servicos-para-manual` | Reformular | Agrupa sete servicos; pode afetar ICS, arquivos offline e armazenamento; dividir e exigir justificativa por servico. | servico |
| `sysmain` | Reformular | Uso elevado de disco nao prova causa; medir antes e preservar por padrao. | servico |
| `pesquisa-indexacao` | Reformular | Pode afetar busca e Outlook; ajustar escopo da indexacao antes de desativar. | servico |
| `aplicativos-em-segundo-plano` | Reformular | Preferencia global pode atrasar notificacoes e sincronizacao; preferir controle por aplicativo. | HKCU |
| `efeitos-visuais` | Reformular | Personalizacao com possivel efeito de responsividade; mascara binaria fixa pode alterar acessibilidade. | HKCU |
| `energia-alto-desempenho` | Reformular | Depende de plano disponivel, carga e energia; sem promessa de FPS. | energia |
| `widgets` | Manter com validacao | Preferencia visual; testar build e estado efetivo. | HKCU |
| `limpar-barra-tarefas` | Reformular | TaskbarAl alterava alinhamento e conflituava com barra-esquerda; remover esta acao e descrever apenas icones realmente tratados. | HKCU |
| `menu-contexto-classico` | Reformular | Override CLSID nao certificado; pode falhar em builds novas. | HKCU |
| `finalizar-tarefa-barra` | Manter manual | Recurso depende de build e rollout; validar disponibilidade. | HKCU |
| `extensoes-de-arquivo` | Manter com validacao | Preferencia de visibilidade; sem promessa de desempenho. | HKCU |
| `explorer-este-pc` | Manter com validacao | Preferencia de abertura do Explorer. | HKCU |
| `pastas-automaticas` | Reformular | Override amplo de tipo de pasta; sem beneficio medido. | HKCU |
| `caminhos-longos` | Reformular | Compatibilidade de apps longPathAware, nao ganho de desempenho. | HKLM |
| `modo-escuro` | Manter com validacao | Preferencia de tema; nao otimizacao de desempenho. | HKCU |
| `numlock-inicializacao` | Reformular | Altera usuario atual e .DEFAULT; separar escopos. | HKU, HKCU |
| `bsod-detalhado` | Reformular | Diagnostico e aparencia de BSOD, nao desempenho; validar parametros por build. | HKLM |
| `notificacoes` | Reformular | Pode ocultar alertas importantes; preferir configuracoes por app. | HKCU |
| `hora-utc-dualboot` | Manter manual | Somente dual boot com RTC UTC confirmado. | HKLM |
| `edge-debloat` | Reformular | Conjunto de politicas de navegador; validar cada politica e evitar sobrescrita. | HKLM |
| `bateria-porcentagem` | Manter manual | Depende de build, hardware e rollout. | HKCU |
| `barra-esquerda` | Manter com validacao | Preferencia de alinhamento; separar de ocultacao de icones. | HKCU |
| `remover-home-galeria` | Reformular | Overrides CLSID nao certificados; testar cada build. | HKCU |
| `arquivos-ocultos` | Manter com validacao | Preferencia de visibilidade; nao liberar arquivos protegidos. | HKCU |
| `verboso-logon` | Manter manual | Politica diagnostica; preservar politica existente. | HKLM |
| `tela-bloqueio-off` | Reformular | Politica depende de edicao; nao modificar autenticacao. | HKLM |
| `teclas-aderencia` | Reformular | Mascara fixa de acessibilidade pode sobrescrever preferencias; preferir UI nativa. | HKCU |
| `mouse-precisao` | Manter manual | Preferencia de entrada; nao inferir melhoria universal de precisao. | HKCU |
| `bloquear-coinstaladores` | Reformular | SearchOrderConfig pode afetar busca de drivers; nao garantir funcionamento do hardware. | HKLM |
| `preferir-ipv4` | Manter manual | Apenas diagnostico de rede especifico; pode alterar conectividade. | HKLM |
| `ia-copilot` | Reformular | SettingsPageVisibility sobrescreve lista inteira e servico pode ter dependencias; separar acoes. | HKLM, servico |
| `recomendacoes-iniciar` | Manter manual | Politica dependente de edicao e efeitos em Spotlight. | HKLM |
| `ocultar-busca-barra` | Manter com validacao | Preferencia visual; validar valor por build. | HKCU |
| `ocultar-visao-tarefas` | Manter com validacao | Preferencia visual; sobrepoe acao equivalente do ajuste de barra. | HKCU |

## Gate de execucao

Nao ampliar presets sem medir beneficios. Revisar as fontes ja registradas na issue #2, uma por acao, quando implementada. Politicas, servicos, energia, drivers, rede e acessibilidade precisam de autorizacao e verificacao especificas na F2. Backups de registro nao certificam recuperacao de efeitos externos. As mudancas desta PR nao substituem a protecao global existente.

## Segunda revisao: decisao de disponibilizacao para os 42 IDs

Base 786a030, CI aprovado. Esta e uma auditoria estatica de mecanismo e risco, nao certificacao de cada valor por documentacao oficial. As referencias gerais ja registradas no comentario 7147175344 da issue #2 sustentam o roteiro (desempenho, powercfg, gpresult/Policy CSP), nao os valores de registro especificos. Nao foram consultadas fontes externas nesta rodada por restricao ao repositorio. Todos os IDs e acoes historicas permanecem identificaveis; a coluna consulta significa que o executor de ajustes recusa nova aplicacao, nao que a funcionalidade do Windows deixa de existir. Todos os perfis, inclusive aliases legados, selecionam apenas extensoes de arquivo. Nenhum ajuste e anunciado como melhoria medida. As preferencias manuais exigem consentimento, contexto e verificacoes de politica; as orientacoes sao caminhos nativos, nao links executados automaticamente.

| ID | Objetivo | Decisao | Risco/limite | Orientacao |
| --- | --- | --- | --- | --- |
| `telemetria` | privacidade | consulta | Mistura preferencias locais, fala e variavel de maquina; nao representa desativacao integral de telemetria. | Configurar Privacidade e seguranca e preferencias do PowerShell separadamente. |
| `historico-atividades` | privacidade | consulta | Politicas administrativas e recursos dependentes de build. | Revisar historico de atividades nas configuracoes autorizadas. |
| `apps-sugeridos` | privacidade | consulta | Politicas de conteudo dependentes de edicao; nao sobrescrever regras. | Revisar recomendacoes nas configuracoes do Windows. |
| `delivery-optimization` | rede | consulta | Desligar P2P pode elevar trafego externo e afetar distribuicao interna. | Consultar configuracoes de Otimizacao de Entrega com o TI. |
| `wpbt` | compatibilidade | consulta | Pode impedir utilitarios OEM legitimos; beneficio nao demonstrado. | Consultar fabricante e administrador. |
| `device-metadata` | compatibilidade | consulta | Pode impedir software de hardware e metadados legitimos. | Revisar configuracao nativa de dispositivos. |
| `bing-no-menu-iniciar` | personalizacao | consulta | Mistura politica e valor dependente da build. | Revisar opcoes de pesquisa disponiveis. |
| `localizacao` | privacidade | consulta | Desativar servico e sensores afeta apps e recursos dependentes. | Revisar permissoes de localizacao por aplicativo. |
| `servicos-para-manual` | desempenho | consulta | Agrupamento de servicos pode afetar ICS, armazenamento e arquivos offline; nao ha medicao. | Medir gargalo e revisar cada servico com o administrador. |
| `sysmain` | desempenho | consulta | Atividade de disco nao prova que SysMain causa lentidao. | Medir atividade e latencia de disco antes de diagnosticar. |
| `pesquisa-indexacao` | desempenho | consulta | Desativacao pode prejudicar Explorer, Outlook e pesquisa. | Revisar escopo de indexacao nas opcoes nativas. |
| `aplicativos-em-segundo-plano` | desempenho | consulta | Restricao global pode interromper sincronizacao e notificacoes. | Revisar consumo e permissoes por aplicativo. |
| `efeitos-visuais` | personalizacao | consulta | Conjunto de valores dependentes de build e preferencias de acessibilidade. | Usar opcoes nativas de efeitos visuais; medir a carga se necessario. |
| `energia-alto-desempenho` | desempenho | manual | Plano pode estar ausente, aumentar consumo, calor e ruido; ganho nao comprovado. | Confirmar plano disponivel, politica e consumo; comparar sob a mesma carga. |
| `widgets` | personalizacao | manual | Preferencia visual dependente da build; nao remove pacote. | Revisar configuracoes da barra de tarefas. |
| `limpar-barra-tarefas` | personalizacao | consulta | Chat depende da build; agrupa visao de tarefas ja disponivel separadamente. | Usar opcoes nativas e o item individual de visao de tarefas. |
| `menu-contexto-classico` | personalizacao | consulta | Override CLSID de shell nao certificado; pode quebrar comportamento. | Usar menu nativo; nao instalar overrides automaticamente. |
| `finalizar-tarefa-barra` | personalizacao | consulta | Depende de build/rollout e permite encerramento sem salvar. | Usar opcoes nativas de desenvolvedor quando disponiveis. |
| `extensoes-de-arquivo` | personalizacao | essencial | Facilita inspecionar nomes e extensoes; nao detecta malware. | Revisar visibilidade de extensoes no Explorer. |
| `explorer-este-pc` | personalizacao | manual | Preferencia de abertura do Explorer; nao acelera o sistema. | Revisar opcoes de pasta. |
| `pastas-automaticas` | personalizacao | consulta | Override de Bags nao certificado e amplo; beneficio nao medido. | Ajustar modelo de pasta pelas propriedades do Explorer. |
| `caminhos-longos` | compatibilidade | consulta | Exige aplicacao compativel e pode afetar maquina/politica. | Validar necessidade do aplicativo com administrador. |
| `modo-escuro` | personalizacao | manual | Tema visual; nao implica economia ou ganho universal. | Revisar Personalizacao > Cores. |
| `numlock-inicializacao` | personalizacao | consulta | Mistura usuario atual e perfil .DEFAULT, com estados dependentes de hardware. | Ajustar preferencia do teclado pela ferramenta nativa. |
| `bsod-detalhado` | diagnostico | consulta | Parametros de tela de falha dependem de build; nao corrigem falhas. | Consultar eventos e dumps autorizados. |
| `notificacoes` | personalizacao | consulta | Pode ocultar alertas importantes e sobrescrever politica. | Ajustar notificacoes por aplicativo. |
| `hora-utc-dualboot` | compatibilidade | consulta | Requer RTC e dual boot confirmados; pode alterar hora de outros sistemas. | Configurar relogio conforme documentacao dos sistemas envolvidos. |
| `edge-debloat` | privacidade | consulta | Conjunto de politicas administrativas de navegador. | Revisar configuracoes do Edge e politicas autorizadas. |
| `bateria-porcentagem` | personalizacao | consulta | Recurso depende de hardware e rollout; valor nao certificado. | Usar configuracoes de bateria/barra se disponivel. |
| `barra-esquerda` | personalizacao | consulta | Alinhamento depende da build; valor anterior nao deve ser reaplicado sem validacao. | Usar Personalizacao > Barra de tarefas > Comportamentos. |
| `remover-home-galeria` | personalizacao | consulta | Overrides CLSID de shell nao certificados. | Revisar opcoes de navegacao do Explorer. |
| `arquivos-ocultos` | personalizacao | manual | Exibe arquivos ocultos comuns; nao libera arquivos protegidos. | Revisar opcoes de exibicao do Explorer. |
| `verboso-logon` | diagnostico | consulta | Escrita em politica de logon; nao aumenta desempenho. | Consultar logs de inicializacao/logon com o administrador. |
| `tela-bloqueio-off` | personalizacao | consulta | Politica dependente de edicao; nao alterar fluxo de bloqueio. | Usar opcoes permitidas de tela de bloqueio. |
| `teclas-aderencia` | acessibilidade | consulta | Mascara fixa de flags pode sobrescrever necessidades de acessibilidade. | Usar Acessibilidade > Teclado. |
| `mouse-precisao` | personalizacao | consulta | Preferencia individual; nao comprova melhoria de precisao ou FPS. | Usar configuracoes de ponteiro e avaliar preferencia pessoal. |
| `bloquear-coinstaladores` | compatibilidade | consulta | Pode prejudicar instalacao de drivers e hardware. | Usar Windows Update e ferramentas autorizadas de drivers. |
| `preferir-ipv4` | rede | consulta | Mudanca na conectividade pode afetar VPN, dominio e IPv6. | Diagnosticar rede sem modificar protocolos. |
| `ia-copilot` | privacidade | consulta | Mistura politicas, visibilidade global de paginas e servico. | Revisar opcoes de IA disponiveis e politicas autorizadas. |
| `recomendacoes-iniciar` | personalizacao | consulta | Politica dependente de edicao; nao sobrescrever regra. | Revisar opcoes do menu Iniciar. |
| `ocultar-busca-barra` | personalizacao | manual | Preferencia visual dependente de build; nao desativa pesquisa. | Revisar configuracoes da barra de tarefas. |
| `ocultar-visao-tarefas` | personalizacao | manual | Preferencia visual; nao desativa desktops virtuais. | Revisar configuracoes da barra de tarefas. |

Metadados por item em data/tweaks.json incluem mecanismo (acoes), escopo derivado, build/edicao declarada, evidencia, risco, verificacao e recuperacao. A selecao essencial e conveniencia, nao uma otimizacao comprovada. A fonte por valor, compatibilidade efetiva, benchmarks e aceite cliente continuam abertos. A protecao global permanece. 

## Terceira revisao (F5): fonte oficial por item e decisao final dos 42 IDs

Data: 25/11/2026. Fecha o item 1 e o item 2 da F5 na issue #2: pesquisa externa de fonte oficial documentada por item e decisao final de catalogo (manter/reformular/remover) registrada nesta matriz. Metodo: cada ID foi conferido contra as acoes reais de `data/tweaks.json` e cada mecanismo foi pesquisado em fontes Microsoft (learn.microsoft.com, support.microsoft.com, blogs.windows.com); o que nao tem documento formal da Microsoft esta dito explicitamente. A tabela de decisao preliminar acima passa a valer so como historico; em caso de duvida prevalece esta matriz.

Criterios aplicados:

- Manter: mecanismo coberto por documentacao oficial e item permanece como esta.
- Manter com nota: item reversivel e registrado em journal, mas parte ou todo o mecanismo nao tem documento formal da Microsoft; a nota registra a lacuna em vez de prometer suporte.
- Reformular: trocar o mecanismo por caminho oficial melhor. Nenhum ID caiu aqui: os mecanismos atuais gravam os valores que o proprio Windows le, e uma politica CSP equivalente nao muda o efeito para um app local; a resposta honesta para chave sem doc formal e a nota, nao uma troca cosmetica.
- Remover: duplicata exata ou mecanismo morto (1 caso abaixo).

| ID | Decisao final | Fonte oficial verificada | Lacuna explicita |
| --- | --- | --- | --- |
| `telemetria` | Manter com nota | Privacy CSP documenta DisableAdvertisingId e AllowInputPersonalization (learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy); Experience CSP documenta DisableTailoredExperiencesWithDiagnosticData (policy-csp-experience); about_Telemetry documenta POWERSHELL_TELEMETRY_OPTOUT (learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_telemetry) | HasAccepted (fala online), RestrictImplicitInkCollection/RestrictImplicitTextCollection, HarvestContacts e Start_TrackProgs sem doc formal; as chaves gravadas sao posicoes de preferencia do usuario, nao as posicoes de politica que a CSP descreve |
| `historico-atividades` | Manter com nota | Privacy CSP (admx-backed) documenta EnableActivityFeed | PublishUserActivities e UploadUserActivities sem pagina propria na Learn (irmas do OSPolicy.admx, uso amplo); dependencia de build ja registrada no catalogo |
| `apps-sugeridos` | Manter com nota | Experience CSP documenta DisableThirdPartySuggestions e DisableTailoredExperiencesWithDiagnosticData | DisableWindowsConsumerFeatures sem artigo em Learn; existe na referencia ADMX (planilha de politicas), nao em pagina web da Microsoft |
| `delivery-optimization` | Manter | DeliveryOptimization Policy CSP documenta DODownloadMode (learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization); valor 0 = HTTP puro, sem peering | nenhuma |
| `wpbt` | Manter com nota | nenhuma pagina da Microsoft documenta DisableWpbtExecution | mitigacao reconhecida na comunidade (usada por WinUtil e outros); manter como consulta com aviso OEM; nao anunciar como recomendacao suportada |
| `device-metadata` | Manter | Manage connections from Windows OS components to Microsoft services (learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services) documenta PreventDeviceMetadataFromNetwork no caminho exato usado | nenhuma |
| `bing-no-menu-iniciar` | Manter com nota | nenhuma doc formal para BingSearchEnabled nem DisableSearchBoxSuggestions | efeito constatado empiricamente e reversivel; sem promessa de suporte |
| `localizacao` | Manter com nota | Windows location service and privacy (support.microsoft.com/en-us/windows/privacy/windows-location-service-and-privacy) documenta o recurso e o servico | lfsvc, SensorPermissionState e SYSTEM\Maps AutoUpdateEnabled sem doc formal das chaves |
| `servicos-para-manual` | Manter com nota | servicos nativos do Windows, reversiveis via journal | nao existe artigo unico da Microsoft cobrindo o conjunto (MapsBroker, StorSvc, SharedAccess, CscService, Fax, RemoteRegistry, RetailDemo); decisao por servico continua do usuario |
| `sysmain` | Manter | learn.microsoft.com/en-us/troubleshoot/windows-client/performance/superfetch-sysmain-service-spikes-cpu documenta o servico e o trade-off | nenhuma |
| `pesquisa-indexacao` | Manter | learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/fix-problems-in-windows-search e .../windows-search-performance-issues documentam WSearch e indexacao | nenhuma |
| `aplicativos-em-segundo-plano` | Manter com nota | nenhuma doc formal para GlobalUserDisabled (BackgroundAccessApplications) | chave funcional em builds atuais, porem nao oficializada; aviso de atraso em sincronizacao e notificacoes mantido |
| `efeitos-visuais` | Manter com nota | caminho nativo documentado: tips-to-improve-pc-performance-in-windows (support.microsoft.com/en-us/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows) | as oito chaves (DragFullWindows, MenuShowDelay, MinAnimate, ListviewAlphaSelect, ListviewShadow, TaskbarAnimations, VisualFXSetting, EnableAeroPeek) nao tem doc formal |
| `energia-alto-desempenho` | Manter | powercfg command-line options (learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options) documenta esquemas de energia e /setactive | nenhuma |
| `widgets` | Manter | Reference for Windows 11 settings (learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11) lista TaskbarDa com caminho e tipo | nenhuma |
| `limpar-barra-tarefas` | Manter com nota | nenhuma das duas chaves consta da referencia atual de settings da Microsoft | TaskbarMn so tem efeito em Win11 21H2/22H2 (Chat/Teams foi removido depois); ShowTaskViewButton reversivel; candidata a limpeza de acao taskbarMn em lote futuro |
| `menu-contexto-classico` | Manter com nota | sem doc formal do override CLSID InprocServer32 vazio | caminho nativo documentado: menu Mostrar mais opcoes (Shift+F10); reversivel e journalled |
| `finalizar-tarefa-barra` | Manter | Windows Insider Blog, canal oficial Microsoft, anuncia o End Task da barra no build 23615 (blogs.windows.com/windows-insider/2024/01/11/announcing-windows-11-insider-preview-build-23615-dev-channel/) | nenhuma |
| `extensoes-de-arquivo` | Manter | File Explorer in Windows (support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1) documenta o toggle de extensoes | HideFileExt sem doc formal; toggle nativo cobre |
| `explorer-este-pc` | Manter | Set File Explorer to open to This PC instead of Quick Access (support.microsoft.com/en-au/windows/set-file-explorer-to-open-to-this-pc-instead-of-quick-access-b2c7d271-027b-b35f-917e-897f66e68e5c) | LaunchTo sem doc formal |
| `pastas-automaticas` | Manter com nota | sem doc formal para FolderType em Bags | tecnica conhecida de folder type fixo; reversivel; sem promessa entre builds |
| `caminhos-longos` | Manter | Maximum Path Length Limitation (learn.microsoft.com/en-us/windows/win32/fileio/maximum-path-length-limitation) documenta LongPathsEnabled | nenhuma |
| `modo-escuro` | Manter com nota | sem doc formal encontrada para AppsUseLightTheme/SystemUsesLightTheme | toggle nativo em Personalizacao > Cores; preferencia visual |
| `numlock-inicializacao` | Manter com nota | sem doc formal para InitialKeyboardIndicators em HKCU e HKU\.DEFAULT | efeito depende de hardware/BIOS; reversivel |
| `bsod-detalhado` | Manter com nota | Stop error information isn't displayed on the blue screen (support.microsoft.com/en-us/topic/stop-error-information-isn-t-displayed-on-the-blue-screen-in-windows-216528fb-94fd-11a2-2675-398ecf5cc237) documenta DisplayParameters | DisableEmoticon sem doc formal |
| `notificacoes` | Manter com nota | Notifications Policy CSP (learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-notifications) cobre politicas de nuvem, nao as chaves usadas | DisableNotificationCenter e ToastEnabled sem doc formal |
| `hora-utc-dualboot` | Manter com nota | You cannot change system time if RealTimeIsUniversal registry entry is enabled (support.microsoft.com/en-us/topic/you-cannot-change-system-time-if-realtimeisuniversal-registry-entry-is-enabled-in-windows-78cf9fbe-eeca-4b06-a67a-2dacdf5189f9) nomeia a chave | artigo descreve a chave em contexto de correcao, nao como recurso suportado; manter como manual |
| `edge-debloat` | Manter | catalogo oficial por politica: learn.microsoft.com/en-us/deployedge/microsoft-edge-policies (EdgeShoppingAssistantEnabled e ShowRecommendationsEnabled conferidos pagina a pagina; as demais seguem o mesmo catalogo) e learn.microsoft.com/en-us/deployedge/microsoft-edge-update-policies (CreateDesktopShortcutDefault) | nenhuma |
| `bateria-porcentagem` | Manter com nota | sem doc formal para IsBatteryPercentageEnabled | rollout dependente de build; manter manual |
| `barra-esquerda` | Manter | Reference for Windows 11 settings lista TaskbarAl com caminho e tipo (mesma pagina citada em widgets) | nenhuma |
| `remover-home-galeria` | Manter com nota | sem doc formal para System.IsPinnedToNameSpaceTree nos CLSIDs de Home/Galeria | mecanismo de pinnagem de namespace conhecido e reversivel; validar por build |
| `arquivos-ocultos` | Manter | Show hidden files (support.microsoft.com/en-us/windows/show-hidden-files-0320fe58-0117-fd59-6851-9b7f9840fdb2) documenta o toggle | valor Hidden sem doc formal propria |
| `verboso-logon` | Manter com nota | Enable verbose startup, shutdown, logon, and logoff status messages (learn.microsoft.com/en-us/troubleshoot/windows-server/performance/enable-verbose-startup-shutdown-logon-logoff-status-messages) e a unica pagina oficial que descreve o comportamento | doc antiga (Server 2003); VerboseStatus sem doc atual; chave legada ainda funcional |
| `tela-bloqueio-off` | Manter com nota | sem doc formal para NoLockScreen | efeito dependente de edicao/build; manter consulta e aviso de que nao e mecanismo suportado |
| `teclas-aderencia` | Manter com nota | sem doc formal para Flags=506 em StickyKeys | toggle nativo em Acessibilidade > Teclado; mascara fixa sobrescreve a preferencia atual do usuario (aviso mantido) |
| `mouse-precisao` | Manter com nota | Change mouse settings (support.microsoft.com/en-us/windows/hardware/input-devices/change-mouse-settings) documenta o toggle de precisao do ponteiro | MouseSpeed/MouseThreshold1/MouseThreshold2 sem doc formal |
| `bloquear-coinstaladores` | Manter com nota | sem doc formal para SearchOrderConfig e DisableCoInstallers | aviso de drivers e hardware mantido |
| `preferir-ipv4` | Manter | Configure IPv6 for advanced users (learn.microsoft.com/en-us/troubleshoot/windows-server/networking/configure-ipv6-in-windows) documenta DisabledComponents, com 0x20 = preferir IPv4 | nenhuma |
| `ia-copilot` | Manter com nota | SettingsPageVisibility (learn.microsoft.com/en-us/windows/configuration/settings/page-visibility), WindowsAI Policy CSP com DisableAIDataAnalysis (learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai), Manage AI features in Notepad com DisableAIFeatures (learn.microsoft.com/en-us/windows/client-management/manage-notepad) e Manage Recall (learn.microsoft.com/en-us/windows/client-management/manage-recall) | servico WSAIFabricSvc sem doc formal; conferir hide:aicomponents contra a lista vigente de URIs por build |
| `recomendacoes-iniciar` | Manter | Start policy settings (learn.microsoft.com/en-us/windows/configuration/start/policy-settings) documenta HideRecommendedSection na Start CSP | nenhuma |
| `ocultar-busca-barra` | Manter com nota | sem doc formal para SearchboxTaskbarMode | preferencia visual dependente de build; reversivel |
| `ocultar-visao-tarefas` | Remover | acao identica (ShowTaskViewButton=0) ja existe em limpar-barra-tarefas: mesma chave, mesmo valor, ver `data/tweaks.json` | duplicata exata; a remocao e mudanca de catalogo (tweaks.json e GUI) para lote posterior; ate la o item segue funcional e apenas manual |

Fechamento: 15 manter, 26 manter com nota, 1 remover. Nenhuma nota acima muda a protecao em vigor: journal, reversao, porte manual/consulta e avisos seguem os mesmos. Lacuna significa ausencia de documento formal da Microsoft, nao ausencia de efeito. Pesquisa e decisao F5 fechadas do lado do executor; teste em cliente e aceite continuam pendentes do usuario.
