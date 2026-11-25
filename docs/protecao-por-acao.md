# F2 - protecao por acao, primeira entrega

Refs #2. Base 0dcec6b8077bf918b6162b05e5653b8c3c37a0e2. A protecao global permanece obrigatoria; a nova camada e defesa adicional, nao substituicao completa.

| Caminho | Verificacao adicionada | Limite |
| --- | --- | --- |
| Registro (aplicacao e reversao com escrita) | Formato de hive; recusa de chaves de politica, alvos sensiveis de seguranca, identidade, servicos e atualizacoes identificados | Nao mapeia todas as politicas efetivas de uma preferencia |
| Servicos | Lista explicita de alvos existentes na V2; valores de inicio validos; dependentes inclusive parados impedem desativacao | Lista nao certifica cada servico como seguro; inventario/impacto/politica ainda precisam de revisao |
| Energia | GUID valido; indicadores locais de politica; erro na consulta recusa mudanca | Nao prova ausencia de GPO/MDM |
| GUI e CLI | Previa de bloqueios por alvo antes de aplicar lote; simulacao preservada; motivo no guia | Nao substitui validacao de runtime nem autorizacao administrativa |
| Outros caminhos | Protecoes anteriores preservadas | F2 ainda incompleta (AppX, recursos, tarefas, WinGet, desinstalacao, manutencao, journals e politicas efetivas) |

Acoes que escrevem diretamente em Policies/PolicyManager ficam somente consulta/simulacao nesta etapa, mesmo em PC pessoal. Journals antigos que exigem nova escrita nestas chaves precisam de revisao manual; estado ja restaurado nao e sobrescrito. Nao se deve usar esta camada para contornar politicas nem remover o modo protegido.

## Gates restantes
- Definir descritores por operacao, escopo/SID, privilegio real, compatibilidade e politica efetiva; avaliar politicas por mecanismo, inclusive preferencias fora de Policies.
- Migrar cada mutacao e cada reversao para a mesma camada; tratar dependencias de recursos, assinatura/proveniencia de instaladores, protecao de dados, tarefas e quarentena.
- Revisar alvos permitidos com evidencias de beneficio, testes de falha e Windows cliente. Ausencia de um indicador de gerenciamento nao autoriza uma mudanca.
- Somente apos paridade e aceite, substituir o bloqueio global; modo diagnostico e autorizacao do TI permanecem.

## Recursos opcionais

Novas acoes de recurso exigem nome na lista de oito recursos expostos e ativacao booleana explicita; desativacao arbitraria nao e permitida. A consulta conservadora de indicadores de politica de servicing precede alteracao e reversao, sem alegar cobertura completa de GPO/MDM. Reversao fora da lista exige revisao manual. Virtualizacao pode interferir com hipervisores e outras cargas; a interface avisa. A protecao global permanece.

## Lote F2 - contrato central e retirada da classificacao global

Base d8bb093 com CI 45519353001 aprovado. Este lote e exclusivo da F2. O identificador legado ModoProtegido significa sessao de diagnostico, falta de autorizacao/elevacao/compatibilidade de base, ou falha ao preparar estado privado/trava. Nao depende mais de classificar o PC como empresarial ou pessoal. O parametro -AutorizarAlteracoes (alias de -Pessoal por compatibilidade) expressa consentimento explicito para a sessao, nao prova autorizacao do TI. A avaliacao central e uma regra de aplicacao, nao uma fronteira de seguranca do Windows.

### Contrato de operacoes

Obter-DescritorOperacao devolve ID, escopo, privilegio, build/edicao, politica, risco, precondicao, backup, verificacao e reversao. Resolver-AutorizacaoOperacao devolve permitido, exige-autorizacao, conflitante, incompativel, desconhecido ou bloqueado, motivo e proximo passo. Operacao nao catalogada e bloqueada. Confirmar-PermissaoAlteracao chama o avaliador no executor. A previa da GUI usa o mesmo contrato sem reconsultas pesadas em cada checkbox; nao e concessao definitiva. A sessao/CLI/portatil compartilham o contrato. A revalidacao de escrita le novamente identidade, arquitetura, build/edicao, sinais relevantes e, para escopo usuario/misto, proprietario do Explorer da mesma sessao; sem correspondencia nao altera HKCU, AppX ou dados do usuario. Registros de contexto dos testes sao mocks fora dos modulos de producao.

| Operacao | Autorizacao geral e checagem especifica | Falha |
| --- | --- | --- |
| estado-local | Consentimento/elevacao, identidade, ACL privada, trava, journal; contexto original do journal | Sem estado/alteracoes; consultas preservadas |
| registro-usuario | SID interativo; alvos/valores revisados, indicadores GPO/MDM relevantes, estado anterior/esperado | Sem escrita; politica conflitante ou desconhecida |
| registro-local / registro-maquina | Contexto completo; planos HKCU restritos, Run dedicado e alvos revisados; protecao de hives | Recusa alvo novo/historico nao revisado |
| servico | Contexto completo, lista e dependentes, comparacao antes/depois | Recusa ou ferramenta nativa |
| tarefa / tarefa-reversao | Nova desativacao bloqueada por identidade funcional nao comprovada; reversao exige assinatura, estado e contexto | Consulta ou revisao manual |
| energia | Contexto, politica e plano existente; snapshot | Recusa se incerto |
| recurso | Contexto, cliente/build/edicao, politica de servicing, lista e estado | Recusa ou recursos nativos |
| appx | SID interativo, Store/Appx/AppLocker, catalogo, NonRemovable/framework/recurso/dependentes; releitura antes de remover | Recusa, reinstalacao manual se nao confirmada |
| winget / consulta-winget | Contexto, politica App Installer, origem registrada/assinatura, ID/fonte/versao e confirmacao | Ferramenta nativa autorizada |
| desinstalar / rastros / path | Contexto, SID quando misto, identidade e assinatura, snapshot de alvo, quarentena | Preservar dados; usar fluxo nativo quando incerto |
| restore / reparo | Contexto, politica de restauracao/servicing, comandos nativos e confirmacao; sem ativar protecao silenciosamente | Recusa |
| temp / dns / hora | Contexto, perfil local confirmado para Temp, estado e confirmacao; nenhum reset generico | Preservar |
| exportar / download | Contexto e SID interativo, consentimento/destino e verificacao propria | Sem exportacao/download |
| diagnostico-admin | Elevacao/autorizacao para comandos de consulta que podem gerar logs nativos; sem reparo solicitado | Consulta indisponivel, nao falha de saude |
| nativo | Apenas abrir ferramenta do Windows; nao eleva nem aplica ajuste automaticamente | Windows impoe seus controles |

Sinais de ingresso, dominio, inscricao MDM, seguranca organizacional e certificados continuam conservadoramente relevantes para mutacoes. Politica de proxy ou fonte de atualizacao (inclusive consulta isolada inconclusiva) nao decide uma preferencia do Explorer nem ponto de restauracao; politicas da propria operacao ainda sao verificadas. Para outros fluxos com dependencias/politicas pouco comprovadas, sinais/inconclusoes relevantes mantem a operacao recusada; nao ha override. Antivirus comum, VPN isolada ou conta registrada sem ingresso nao sao prova de gerenciamento. GPO/MDM efetivos podem existir fora dos indicadores consultados; ausencia de sinal nao prova ausencia de politica. Aplicacao e reversao nao substituem administradores, ACLs, WDAC/AppLocker ou validacao em cliente. As reconsultas podem ser lentas; responsividade pertence a F1. Operacoes delegadas a instalador/console nativo nao sao transacoes atomicas e verificacoes nao eliminam corridas. Exportacao sanitizada, dependencia completa e resultados individuais do WinGet continuam respectivamente em F3/F6. Nenhum release foi publicado.

### Aceite F2

Testes no CI incluem matriz dos descritores, IDs desconhecidos, Home/Pro/Enterprise, build/arquitetura/SID, falta de elevacao/consentimento, GPO/MDM positivos e inconclusivos por operacao, releitura de identidade/edicao/sinais, executor e reversao sem tocar no alvo recusado, compatibilidade de recursos e AppX, interfaces e CLI/portatil, integracao real descartavel com contexto cliente sintetico, recusa de desativar tarefa nao revisada e recuperacao de snapshot. Os testes de integracao nao simulam o Windows cliente completo nem a politica real de uma empresa. Nao marcar aceite F2 concluido antes do CI do commit e teste manual em Windows 10/11, usuario padrao e admin autorizado, credenciais alternativas, dominio/MDM de laboratorio e politicas locais. O lote foi preparado sem disparos intermediarios de CI.
