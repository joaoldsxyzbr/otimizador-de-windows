# F3 - identidade de journal e verificacao de reversao

Refs #2. Primeira entrega: novos journals usam esquema 2, vinculados ao SID efetivo do processo, MachineGuid local e visao do registro (32/64 bits). A reversao e a confirmacao manual recusam contexto divergente ou esquema desconhecido antes de gravar. O identificador de maquina fica no journal local protegido; nao incluir esse campo em exportacoes de diagnostico nem publicar journals de maquinas reais.

O MachineGuid nao e prova criptografica de identidade (pode ser clonado); e uma barreira contra erros de contexto. O esquema legado permanece legivel e reversivel pelas regras anteriores, sem garantia de identidade. Nao altera o formato dos itens antigos. Uma nova sessao nao inicia se o contexto nao puder ser identificado.

A reversao de registro agora verifica o tipo/conteudo restaurado ou ausencia do valor, antes de reportar sucesso. Permanecem os conflitos detectados no snapshot e o marcador de reversao incerta.

Pendentes: identidade por alvo em journals antigos, validacao de caminho/ACL do arquivo e backups individuais, estado de aplicacao por acao, recuperacao automatizada de falhas parciais, verificacao de outros tipos de reversao, compatibilidade com exportacoes e aceite em Windows cliente. Nao e certificacao de rollback integral.

## Validacao adicional do arquivo

A recuperacao, confirmacao manual e inventario validam o arquivo JSON diretamente dentro da pasta de estado, rejeitam redirecionamento e verificam ACL esperada do arquivo e da pasta. Journals antigos sem ACL esperada ficam indisponiveis para restauracao automatica. Esta barreira nao autentica o conteudo contra um administrador e nao valida todos os backups referenciados; esses requisitos permanecem pendentes. Testes unitarios exercitam caminhos externos/redirecionados; a integracao real exercita journals novos com ACL herdada.
