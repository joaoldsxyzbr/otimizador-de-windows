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
