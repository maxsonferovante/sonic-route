# Sonic Route

Utilitário de barra de menus para ajustar volume, mute e saída de áudio por aplicação no macOS 26 ou superior.

Licenciado sob a [Licença MIT](LICENSE).

## Estado do protótipo

O app descobre processos com saída de áudio e usa os identificadores de objeto de processo do Core Audio para criar um process tap. Um I/O proc do Core Audio lê o aggregate device privado em um ring buffer lock-free limitado; um `AVAudioSourceNode` alimenta o mecanismo de saída, onde um mixer aplica o ganho e encaminha o fluxo ao dispositivo escolhido. Esse caminho usa APIs públicas, não simula controles e não abre a entrada do microfone. O macOS solicita permissão de gravação de áudio do sistema na primeira captura. Helpers são agrupados sob o app hospedeiro quando estão aninhados no bundle dele ou usam o sufixo convencional `.helper` no bundle ID, então o áudio do navegador é identificado pelo navegador, sem trocar o nome pelo site de mídia.

No Mac de validação, o Spotify foi descoberto e o Core Audio criou seu tap privado e aggregate device após a autorização de gravação de áudio do sistema. A saída audível e a latência ainda precisam de uma verificação por escuta, e o roteamento do FaceTime precisa ser testado durante uma chamada.

## Demonstração

Capturas de tela feitas com o app macOS em execução:

<table>
  <tr>
    <td align="center"><strong>Controles de áudio por app</strong><br><img src="docs/screenshots/menu-bar-panel.png" alt="Painel do Sonic Route com controles separados para Microsoft Edge e Spotify" width="320"></td>
    <td align="center"><strong>Configurações</strong><br><img src="docs/screenshots/settings.png" alt="Painel de configurações do Sonic Route" width="320"></td>
  </tr>
</table>

## Requisitos

- macOS 26 ou superior
- Xcode 26 para abrir e executar o projeto `.xcodeproj`
- Swift 6.0 ou superior para os comandos do Swift Package Manager

## Executar

1. Abra `SonicRoute.xcodeproj` no Xcode.
2. Selecione o scheme **SonicRoute** e execute o app.
3. Clique no ícone de forma de onda na barra de menus.
4. Ao controlar um app pela primeira vez, permita a gravação de áudio do sistema em **Ajustes do Sistema → Privacidade e Segurança**.

O target é um agente de barra de menus, sem ícone no Dock.

## Distribuição em DMG autoassinado

Este projeto pode criar o app e o DMG autoassinados para distribuição direta. No Acesso às Chaves, escolha **Assistente de Certificados → Criar um Certificado**, dê o nome `Sonic Route Distribution` e selecione **Self Signed Root** e **Code Signing**. Crie a identidade uma única vez e mantenha a chave privada no Acesso às Chaves do responsável pela assinatura; nunca a versione, exporte ou distribua.

```sh
SIGNING_IDENTITY="Sonic Route Distribution" scripts/package-dmg.sh
```

O script compila o app Release, assina o framework embutido e o app com essa identidade, cria um DMG para arrastar o app até Aplicativos, assina o DMG com a mesma identidade e verifica as assinaturas. O pacote é gravado em `dist/`.

Este fluxo autoassinado não ativa o Hardened Runtime. O runtime ativa a validação de bibliotecas, que exige Team IDs da Apple iguais para o app e seus frameworks; um certificado autoassinado não tem Team ID da Apple, e o runtime impede o app de carregar o framework. Este fluxo serve apenas para a distribuição sem notarização aceita aqui. Consulte a [documentação da Apple sobre validação de bibliotecas](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation).

Use o mesmo certificado e bundle identifier nas atualizações para que o macOS reconheça a identidade do app ao controlar a permissão de captura de áudio. Cada pessoa ainda precisa permitir a gravação de áudio do sistema no próprio Mac. Uma identidade autoassinada não comprova ao Gatekeeper quem publicou o app e o pacote não é notarizado; o Gatekeeper pode exigir que a pessoa autorize a abertura manualmente. A notarização da Apple exige um certificado Developer ID Application, portanto este fluxo não permite notarizar. Consulte o [guia de assinatura de código da Apple](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) e os [requisitos de notarização](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

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
- **CoreAudioSessionService**: resolve helpers aninhados e bundle IDs com o sufixo convencional `.helper` para o app hospedeiro quando possível; outros helpers ainda podem aparecer com a própria identidade de processo. Cria um tap privado para os identificadores de objeto de áudio ativos de cada app, lê o tap por um I/O proc do aggregate device e encaminha o áudio por um `AVAudioSourceNode` e `AVAudioEngine` ao dispositivo escolhido. O alvo é atualizado quando esses objetos de processo mudam.
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
