# F4 - central de saude: alertas, fontes oficiais e limites

Refs #2. Auditoria de 25/11/2026 dos indicadores da pagina Inicio (Avaliar-SaudeLocal e amostras de Medir-GargalosLocais em src/modules/sistema.ps1): consulta usada, fonte oficial do que a consulta mede, criterio de estado e comportamento quando o dado esta ausente. Nenhum limiar abaixo tem origem oficial: sao valores de triagem propria deste app.

## Indicadores da avaliacao local

| indicador | consulta usada | fonte oficial | criterio de estado (interno) |
|---|---|---|---|
| ram | Win32_OperatingSystem (FreePhysicalMemory, TotalVisibleMemorySize) | [Win32_OperatingSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem) | atencao quando livre < 10% da amostra; informacao quando total visivel < 8 GB |
| disco | Win32_LogicalDisk (FreeSpace, Size do SystemDrive) | [Win32_LogicalDisk](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk) | atencao quando livres < 15% ou < 5 GB |
| inicio | Win32_StartupCommand (contagem) | [Win32_StartupCommand](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-startupcommand), [Configurar aplicativos de inicializacao no Windows](https://support.microsoft.com/pt-br/windows/experience/startup-boot/configure-startup-applications-in-windows) | sempre informacao; quantidade nao mede impacto |
| reinicio | chaves CBS RebootPending e Windows Update RebootRequired | chaves sem documentacao publica formal da Microsoft; o recurso oficial DSC [Microsoft.Windows/RebootPending](https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/microsoft/windows/rebootpending/?view=dsc-3.0) avalia indicadores equivalentes | atencao quando presente; indisponivel quando a consulta falha |
| bateria | Win32_Battery (presenca); BatteryStaticData/BatteryFullChargedCapacity quando correlacionaveis | [Win32_Battery](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-battery), estruturas [BATTERY_WMI_STATIC_DATA](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_static_data) e [BATTERY_WMI_FULL_CHARGED_CAPACITY](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_full_charged_capacity) | informacao ou indisponivel; sem limiar de saude |
| amostras de cpu/ram/paginacao/fila/io | contadores do provedor Win32_PerfFormattedData | [Win32_PerfFormattedData](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-perfformatteddata) | aviso quando amostras incompletas; fila e I/O sem limiar universal |

## Revisao contra o criterio original (dado indisponivel nao e zero nem estado saudavel)

- Os seis indicadores acima tem ramo proprio para consulta falha ou dado inconsistente (estado indisponivel com orientacao, sem recomendar limpeza ou ajuste).
- O snapshot da pagina exibe Indisponivel no lugar de inventar numero: host, cpu, gpu, ram, disco, uptime, pontos de restauracao, ambiente e bateria.
- A contagem de atencao da triagem e explicitamente "nesta amostra" e nao e nota de saude.
- Revisados um a um em 25/11/2026 contra o codigo do branch de integracao; ao mudar Avaliar-SaudeLocal ou Obter-SnapshotInicio, atualizar esta tabela.

## Efeito e medicao

- Nenhuma orientacao da central cita efeito ou ganho: todas apontam investigacao por amostras ou ferramenta nativa. A amostra unica e triagem.
- Janelas reais de amostragem estao no botao de amostras (Medir-GargalosLocais): serie com avisos de amostras incompletas e celulas vazias declaradas como indisponiveis, sem limiar inventado para fila/I/O de disco.
- Medicao de efeito de ajuste e escopo de F5: exige antes/depois com mesma carga e multiplas amostras. Enquanto nao existir, nenhuma recomendacao desta central pode citar efeito.
