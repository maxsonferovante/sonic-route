# Sonic Route

Utilitário de barra de menus para ajustar volume, mute e saída de áudio por aplicação no macOS 26 ou superior.

Licenciado sob a [Licença MIT](LICENSE).

## Estado do protótipo

O app descobre processos com saída de áudio e usa Core Audio process taps para capturar o som de um bundle identifier. Um `AVAudioEngine` local aplica o ganho e reproduz o fluxo no dispositivo selecionado. Esse caminho usa APIs públicas e não simula controles. O macOS solicita permissão de gravação de áudio do sistema na primeira captura.

Spotify e FaceTime são alvos de compatibilidade para validação. A execução de chamadas e testes com dispositivos físicos não foi feita neste ambiente; a compatibilidade real depende de validação em um Mac com Xcode, áudio ativo e esses apps em uso.

## Requisitos

- macOS 26 ou superior
- Xcode 26 para abrir e executar o projeto `.xcodeproj`
- Swift 6.0 ou superior para os comandos do Swift Package Manager

## Executar

1. Abra `SonicRoute.xcodeproj` no Xcode.
2. Selecione o scheme **SonicRoute** e execute o app.
3. Clique no ícone de forma de onda na barra de menus.
4. Ao controlar um app pela primeira vez, permita a gravação de áudio do sistema em **Ajustes do Sistema → Privacidade e Segurança**.

O target é um agente de barra de menus, sem ícone no Dock. Para distribuição direta, selecione uma equipe de assinatura Developer ID no Xcode e siga o fluxo de archive e notarização da Apple. A assinatura e a notarização não são geradas neste projeto.

## Testes

Os testes unitários usam Swift Testing e cobrem regras de volume, fallback de saída, filtragem de apps, persistência por bundle identifier e restauração de controles quando um app começa a emitir áudio.

```sh
swift test
```

No Xcode, selecione o scheme **SonicRoute** e use **Product → Test**.

## Arquitetura

- **MenuBarPanelView** e **ApplicationRowView**: painel compacto de SwiftUI, controles por app e estados vazios, carregamento e erro.
- **MenuBarViewModel**: coordena as linhas, preferências, saídas e atualizações periódicas.
- **AudioDeviceServicing**: enumera dispositivos de saída e identifica a saída padrão.
- **AudioSessionServicing**: descobre processos com áudio ativo e controla sessões por bundle identifier.
- **CoreAudioSessionService**: cria um tap privado por app, agrega o tap como entrada e encaminha o áudio pelo `AVAudioEngine` ao dispositivo escolhido.
- **AppAudioPreferenceStore**: persiste volume, mute e saída por bundle identifier.
- Protocolos de serviço permitem testar estado e regras sem depender de hardware de áudio.

O fluxo de áudio fica na memória e não é gravado nem enviado pela rede. O volume é aplicado no mixer local. Ao desconectar a saída escolhida, o app usa a saída padrão do macOS e volta à saída preferida quando ela reaparecer.

## Permissões e limitações conhecidas

- O target declara `NSAudioCaptureUsageDescription`. A primeira leitura de um tap exige consentimento do macOS para gravação de áudio do sistema. Se a permissão for negada ou a sessão não iniciar, o app mostra o erro e mantém a aplicação original sem encaminhamento ativo.
- O macOS não fornece um setter público de volume ou saída diretamente para o processo de outro app. O protótipo silencia a saída original enquanto o tap é lido e reproduz o fluxo capturado; essa passagem pode adicionar latência.
- A compatibilidade varia por app, formato de áudio, conteúdo protegido e dispositivo. FaceTime e Spotify precisam ser verificados com áudio real antes de prometer suporte amplo.
- O app controla áudio de saída. O microfone de chamadas continua sob controle do macOS.
- Sons do Sistema não aparecem como uma aplicação independente, pois o macOS não documenta uma sessão de processo estável com volume e mute próprios para eles.
- A primeira versão não instala driver virtual. Taps de Core Audio fazem a captura por processo; um driver HAL separado adicionaria instalação privilegiada sem substituir essa captura.

## Estrutura

```text
Sources/
  SonicRoute/       # entrada do app e views SwiftUI/AppKit
  SonicRouteCore/   # modelos, regras, serviços e view model
Tests/
  SonicRouteCoreTests/
```
