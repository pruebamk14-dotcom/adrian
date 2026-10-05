# Sniper Duels: Elite — Edición Halloween 🎃

Juego de duelos de francotirador 1v1 para Roblox, inspirado en *Sniper Duels* pero con más profundidad: balística real, mira telescópica con respiración, ranked con ELO, mapas simétricos y un servidor autoritativo contra trampas.

Todo está escrito en **Luau** y se sincroniza con **Rojo**. No necesita assets externos: el lobby, las arenas y los rifles se generan por código, así que funciona nada más abrirlo.

## Qué lo hace mejor que Sniper Duels

| Característica | Sniper Duels | Elite |
| --- | --- | --- |
| Disparo | Hitscan | **Balas con velocidad y caída**, simuladas igual en cliente y servidor |
| Red | Lo valida el cliente | **El servidor es autoritativo**, con compensación de lag (rebobina a los rivales hasta 450 ms) |
| Daño | Fijo | Por zona (cabeza / torso / extremidades) y con caída de daño según el arma |
| Mira | Zoom simple | Zoom variable, **sway, aguantar la respiración** (Shift), quickscope con penalización de dispersión |
| Contra-juego | — | **Destello de la mira**: ves un brillo cuando un rival te está apuntando |
| Anti-camping | — | A los 35 s se revela la posición de los dos jugadores; si se acaba el tiempo, gana quien tenga más vida |
| Matchmaking | Pads | Pads casuales + **cola ranked por ELO** con ventana que se amplía con la espera |
| Progresión | — | Niveles, monedas, 4 rifles desbloqueables, 12 skins en 5 rarezas, rachas con bonus |
| Mapas | Fijos | Arenas **simétricas** (justas para ambos lados) con 4 temas, entre ellos *Lost Hill* |
| Persistencia | — | DataStore con session-lock, autoguardado, reintentos y ranking global |

## Novedades de la edición Halloween

- **Modo solo contra bot con IA** (botón *VS BOT*): Práctica, Fácil, Normal, Difícil y Pesadilla. El bot es un francotirador con cabeza de calabaza que usa exactamente las mismas armas y reglas que un jugador: busca cobertura, te detecta con línea de visión real, adelanta tus movimientos, compensa la caída de la bala y se le ve el destello de la mira.
- **Gráficos**: terreno real con hierba animada, colinas, nubes, niebla, iluminación *Future*, bloom, rayos de sol, corrección de color, partículas (humo, chispas, polvo, niebla, burbujas), casquillos, rastro de bala, temblor de cámara, desenfoque al apuntar y desaturación con poca vida.
- **Halloween**: arenas *Cementerio Olvidado*, *Granja de Calabazas*, *Mansión Embrujada* y *Bosque Maldito*; calabazas con cara que parpadean, tumbas, criptas, árboles muertos, espantapájaros, calderos, telarañas, murciélagos, brasas flotantes, relámpagos, fantasmas al eliminar y fuente *Creepster*.
- **Caramelos 🍬**: moneda del evento para la **caja de Halloween**, con 8 skins nuevas (de Calabaza a *Jinete sin cabeza*, mítica).
- **Monedas al subir de nivel**: 100 + 25 × nivel en cada nivel.
- **Tienda premium**: modelos 3D giratorios, barras de estadísticas, ofertas destacadas, ruleta de cajas, packs de monedas y VIP.
- **Intercambios y regalos** de skins y armas de tienda entre jugadores.
- **Monetización**: pase VIP (x2 monedas y caramelos) y productos de Robux (packs de monedas, pack de caramelos y armas exclusivas).

## Monetización: cómo activar los pagos con Robux

1. Publica el juego (*File → Publish to Roblox*).
2. Ve a [create.roblox.com](https://create.roblox.com) → tu experiencia → **Monetización**.
3. Crea un **Pase** llamado "VIP" y estos **Productos para desarrolladores**: `Coins1000`, `Coins5000`, `Coins15000`, `Candy500`, `WeaponReaper` y `WeaponObsidian`.
4. Copia cada ID en `src/shared/Config/GameConfig.luau`, en la sección `Monetization` (los que tengan 0 aparecen como "no configurado").
5. Ajusta `RobuxPrices` para que coincidan con los precios que pusiste.

Las compras se entregan de forma segura: no se entregan dos veces y se guardan antes de confirmarlas a Roblox. **Las armas de pago no hacen más daño**: todas matan igual, así que no es pay-to-win.

## Intercambios

En el menú **🔄 TRADE** ves a los jugadores del servidor:
- **Intercambiar**: cada uno añade objetos, los dos pulsan LISTO y, tras una cuenta atrás de 4 s, se hace el cambio. Si alguien cambia su oferta, se quita el LISTO de los dos (contra estafas).
- **Regalar**: envías una skin o un arma de tienda sin pedir nada a cambio.

Las armas que se desbloquean por nivel no se pueden intercambiar.

## Estructura

```
sniper-duels/
├── default.project.json        # mapa de Rojo
├── src/
│   ├── shared/                 # ReplicatedStorage.Shared
│   │   ├── Config/
│   │   │   ├── GameConfig.luau # TODOS los valores ajustables
│   │   │   ├── Weapons.luau    # Intervention, Viper, Tempest, Leviathan
│   │   │   └── Skins.luau      # skins + rarezas + tirada de cajas
│   │   ├── Ballistics.luau     # trayectoria, segmento-vs-OBB, dispersión
│   │   ├── GunBuilder.luau     # modelo del rifle (reemplazable por mesh)
│   │   ├── Net.luau            # remotes
│   │   ├── Rank.luau           # rangos, ELO, curva de XP
│   │   └── Signal.luau
│   ├── server/                 # ServerScriptService.Server
│   │   ├── init.server.luau
│   │   ├── World/
│   │   │   ├── Props.luau          # calabazas, tumbas, árboles, criptas...
│   │   │   └── Environment.luau    # iluminación, cielo, niebla, terreno
│   │   └── Services/
│   │       ├── DataService         # guardado + session lock
│   │       ├── ArenaService        # lobby + arenas procedurales
│   │       ├── HitboxHistory       # historial para la compensación de lag
│   │       ├── CombatService       # disparo, balas, daño
│   │       ├── DuelService         # rondas, recompensas, ELO
│   │       ├── MatchmakingService  # pads + cola ranked
│   │       ├── ShopService         # cajas, armas por monedas, equipar
│   │       ├── LeaderboardService  # ranking global
│   │       ├── BotService          # IA del modo solo
│   │       ├── MonetizationService # VIP y productos de Robux
│   │       └── TradeService        # intercambios y regalos
│   └── client/                 # StarterPlayerScripts.Client
│       ├── init.client.luau
│       ├── ClientState.luau
│       ├── UI/Make.luau            # helper + tema visual
│       ├── UI/ShopUI.luau          # tienda premium
│       ├── UI/TradeUI.luau         # intercambios y regalos
│       └── Controllers/
│           ├── WeaponController    # viewmodel, mira, recoil, input, móvil
│           ├── EffectsController   # trazadores, impactos, destello de la mira
│           ├── HUDController       # HUD de combate
│           ├── MenuController      # lobby: perfil, VS BOT, arsenal, ranking
│           └── AmbientController   # murciélagos, relámpagos, luces
```

## Cómo abrirlo

1. Instala [Aftman](https://github.com/LPGhatguy/aftman) y ejecuta `aftman install` (instala Rojo, Selene y StyLua).
2. En Roblox Studio instala el plugin de Rojo.
3. Ejecuta:
   ```bash
   cd sniper-duels
   rojo serve
   ```
4. En Studio pulsa **Rojo → Connect**.
5. **Para probar tú solo:** pulsa **Play** y luego **🎃 VS BOT** → elige la dificultad.
6. Con 2 jugadores: **Test → Clients and Servers → 2**: subid los dos a un par de pads, o pulsad **RANKED** en los dos clientes.

Para generar un archivo de lugar: `rojo build -o SniperDuelsElite.rbxl`.

> Para que se guarden los datos en Studio, activa *Game Settings → Security → Enable Studio Access to API Services*. Sin eso, el juego funciona igual pero los datos solo viven en memoria.

## Controles

| Acción | PC | Mando | Móvil |
| --- | --- | --- | --- |
| Disparar | Clic izquierdo | R2 | Botón DISPARAR |
| Apuntar | Clic derecho (mantener o alternar) | L2 | Botón MIRA |
| Zoom | Z / rueda | Y | Botón ZOOM |
| Recargar | R | X | Botón R |
| Respirar / correr | Shift | L3 | — |

## Ajustar el juego

Todo lo que se ajusta está en `src/shared/Config/`:

- **GameConfig**: rondas para ganar, tiempos, recompensas, K del ELO, compensación de lag, precio de las cajas, IDs de sonidos (vacíos por defecto; pon tus `rbxassetid://`).
- **Weapons**: daño por zona, velocidad y gravedad de la bala, cadencia, cargador, zoom, sway, retroceso, nivel de desbloqueo.
- **Skins**: colores, materiales, rareza y probabilidades.

### Usar mapas o modelos propios

- **Arenas**: crea `Workspace/Arenas/<Modelo>` con dos partes `SpawnA` y `SpawnB`. Si esa carpeta existe, no se generan arenas.
- **Lobby**: crea `Workspace/Lobby` con `LobbySpawn` y pares de pads `PadA_1`/`PadB_1`, `PadA_2`/`PadB_2`, etc.
- **Rifle**: sustituye `GunBuilder.Build` por un modelo importado. Solo tiene que tener un `PrimaryPart` mirando a −Z, los Attachments `Muzzle` y `Ejection`, y una pieza `ScopeLens` (para el destello).
- **Desactivar Halloween**: pon `HalloweenEvent = false` en `GameConfig` para volver a las arenas y la iluminación normales.

### Sonidos

Vienen activados el del hitmarker y el de la cuenta atrás, que usan sonidos internos de Roblox. Los demás (`Fire`, `Bolt`, `Reload`, `Thunder`...) están vacíos: busca sonidos gratis en la **Toolbox de Studio → Audio** (por ejemplo "sniper shot" o "thunder"), copia su ID y pégalo en `GameConfig.Sounds` como `rbxassetid://ID`. Usa solo audios públicos para que funcionen en tu juego.

## Seguridad (anti-trampas)

- El cliente solo envía `origen, dirección, tiempo`. Munición, cadencia, recarga, daño y muertes los decide el servidor.
- El origen tiene que estar a menos de 10 studs de la cabeza del tirador; el tiempo del disparo se limita a 450 ms hacia atrás.
- Las balas se simulan en el servidor en tiempo real contra las hitboxes rebobinadas de los rivales.
- Las compras y los equipamientos se validan en el servidor (nivel, inventario, enfriamiento).
- Ningún servidor puede detectar un aimbot al 100 %. Si quieres, añade heurísticas en `CombatService.onFire` (por ejemplo, tasa de headshots o velocidad de giro).

## Ideas para seguir

- Killcam (con `HitboxHistory` ya tienes los datos para reproducirla).
- Modo espectador de duelos en curso desde el lobby.
- Game Passes / Developer Products para comprar monedas.
- Animaciones propias (`Animator`) para sustituir la pose de brazos por código.
