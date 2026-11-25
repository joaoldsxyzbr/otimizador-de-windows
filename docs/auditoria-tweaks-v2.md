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
