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
