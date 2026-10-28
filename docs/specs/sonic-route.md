# Sonic Route — Especificação

## Problem Statement

O macOS oferece controles globais de volume e saída, mas o usuário precisa controlar cada aplicação separadamente. Isso impede, por exemplo, ouvir música em uma caixa externa enquanto participa de uma chamada pelos alto-falantes ou fones do Mac, ou silenciar somente a chamada sem alterar os outros apps.

## Solution

Um utilitário nativo de barra de menus lista aplicações com áudio ativo e oferece volume, mute e seleção de saída por app. As preferências ficam salvas por bundle identifier e são reaplicadas quando o app volta a emitir áudio. O primeiro protótipo usa process taps do Core Audio e um `AVAudioEngine` local, sem instalar um driver.

## User Stories

1. Como usuário do Mac, quero abrir o painel pelo ícone da barra de menus, para controlar áudio sem manter uma janela principal aberta.
2. Como usuário do Mac, quero ver apps que estejam emitindo áudio, para encontrar rapidamente o que posso controlar.
3. Como usuário do Mac, quero poder mostrar todos os apps abertos, para configurar um app antes de iniciar a reprodução.
4. Como usuário do Mac, quero reconhecer cada app pelo ícone e nome, para evitar ajustar o app errado.
5. Como usuário do Mac, quero ajustar o volume de um app sem alterar os outros, para equilibrar música, jogos e chamadas.
6. Como usuário do Mac, quero ver o nível de volume em porcentagem, para entender o valor aplicado.
7. Como usuário do Mac, quero silenciar e reativar um app sem perder seu nível salvo, para interromper rapidamente um som e recuperá-lo depois.
8. Como usuário do Mac, quero encaminhar cada app para uma saída diferente, para separar música e chamadas entre dispositivos.
9. Como usuário do Mac, quero escolher alto-falantes internos, Bluetooth, HDMI, AirPlay, USB e outras saídas disponíveis, para usar os dispositivos conectados ao Mac.
10. Como usuário do Mac, quero usar a saída padrão do sistema quando a saída escolhida desconectar, para manter o áudio audível.
11. Como usuário do Mac, quero que o app volte automaticamente à saída que escolhi quando ela reaparecer, para preservar minha configuração.
12. Como usuário do Mac, quero que volume, mute e saída sejam restaurados por bundle identifier, para manter minhas preferências entre execuções.
13. Como usuário do Mac, quero iniciar o utilitário junto ao macOS quando habilitado, para ter os controles disponíveis após iniciar sessão.
14. Como usuário do Mac, quero alternar entre ver só apps ativos ou todos os apps abertos, para ajustar o tamanho da lista.
15. Como usuário do Mac, quero habilitar ou desabilitar a restauração de preferências, para controlar como as configurações antigas são aplicadas.
16. Como usuário do Mac, quero abrir o painel por um atalho global opcional, para acessar os controles sem procurar o ícone.
17. Como usuário do Mac, quero receber uma explicação e um caminho para Ajustes de Privacidade quando a captura for negada, para entender por que o controle não foi aplicado.
18. Como usuário do Mac, quero ver estados de carregamento, erro, lista vazia e falta de saídas externas, para saber o que o app detectou.
19. Como usuário do Mac, quero que o Sonic Route não apareça como um app controlável, para evitar que ele capture a própria saída encaminhada.
20. Como usuário do Mac, quero manter o microfone da chamada sob controle do macOS, para que a primeira versão ajuste somente a saída de áudio.

## Implementation Decisions

- O app é um agente de barra de menus feito com Swift, SwiftUI e AppKit, com um painel compacto no estilo do macOS 26.
- A interface usa MVVM e serviços separados para descobrir dispositivos, descobrir e encaminhar sessões de áudio e persistir preferências.
- Protocolos isolam as APIs de áudio, o armazenamento e os serviços de início de sessão e atalho, permitindo testes sem hardware real.
- O controle de sessão usa Core Audio process taps filtrados por bundle identifier. Um `AVAudioEngine` aplica ganho e envia a captura para a saída escolhida.
- A primeira versão não instala driver de áudio. Quando uma preferência requer processamento, o app pede a permissão do macOS para captura de áudio do sistema.
- Sem preferência de saída, o app usa a saída padrão. Saídas preferidas indisponíveis caem para o padrão e voltam a ser usadas quando reaparecem.
- O painel mostra apps com áudio ativo por padrão. Uma configuração permite mostrar todos os apps abertos.
- Volume, mute e saída são salvos por bundle identifier. A restauração automática pode ser desabilitada.
- O início junto ao macOS e o atalho global são opcionais e começam desabilitados.
- “Sons do Sistema” não é apresentado como uma aplicação individual.
- A distribuição pretendida é fora da Mac App Store, com notarização Developer ID quando houver uma equipe de assinatura configurada.

## Testing Decisions

- Um bom teste observa comportamento externo: ganho efetivo, mute sem perder o volume salvo, escolha e fallback de saída, filtro de descoberta, persistência por bundle identifier e aplicação automática das preferências quando um app começa a emitir áudio.
- Regras de volume e saída, persistência por bundle identifier e estado dos controles com protocolos de dispositivo e sessão são os três seams aprovados para testes.
- Os testes usam Swift Testing e serviços falsos para não depender de dispositivos de áudio conectados.
- Spotify e FaceTime devem ser validados com áudio real em um Mac com macOS 26. A suíte unitária não confirma compatibilidade de taps, latência ou comportamento de cada app.

## Out of Scope

- Instalação de driver HAL ou DriverKit no MVP.
- Controle de microfone ou do áudio de entrada de chamadas.
- Volume e mute por som individual do sistema.
- Gravação persistente, envio de áudio pela rede ou serviços em nuvem.

## Further Notes

O macOS não oferece um setter público de volume ou roteamento diretamente para outro processo. O protótipo captura a saída do processo e a reproduz pelo mecanismo local, o que pode introduzir latência ou incompatibilidade com certos formatos, conteúdo protegido e apps. O comportamento com Spotify e FaceTime e a latência ainda precisam de validação em hardware real. O projeto declara o motivo de captura de áudio e solicita consentimento ao macOS.
