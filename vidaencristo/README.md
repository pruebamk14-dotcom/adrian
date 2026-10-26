# Iglesia Bautista Vida en Cristo — Sitio web

Sitio estático (HTML + CSS + JS, sin dependencias) para la Iglesia Bautista Vida en Cristo, South Houston, Texas. Pastor: Liván Quintana.

## Ver el sitio en tu computadora

```bash
cd vidaencristo
python3 -m http.server 8000
# abre http://localhost:8000
```

> El diario cifrado usa WebCrypto, que exige `https://` o `localhost`.

## Publicarlo

Sube la carpeta `vidaencristo/` tal cual a cualquier hosting estático: Hostinger, Netlify, Vercel, GitHub Pages o Cloudflare Pages.

## Qué editar

Todo lo que cambia a menudo está en **`assets/js/config.js`**:

| Campo | Qué es |
|---|---|
| `address` | Dirección exacta del templo (mapa y botón "Cómo llegar") |
| `services` | Cultos semanales (alimentan el contador regresivo y los horarios) |
| `youthEvents`, `womenEvents` | Actividades de jóvenes y de mujeres (las pasadas se ocultan solas) |
| `gallery` | Fotos de la galería |
| `pastorEmail` | Correo del pastor para las peticiones confidenciales |
| `prayerApi` | URL del servidor de oración (ver abajo) |

### Fotos
Descarga las fotos del Facebook de la iglesia y guárdalas en `assets/img/`:
- `pastor.jpg`: foto del pastor y su esposa (vertical, 4:5).
- `foto1.jpg` … `foto6.jpg`: galería (o cambia los nombres en `config.js`).

Mientras no estén, el sitio muestra marcadores elegantes. La sección "En vivo" incrusta la página de Facebook oficial, así que las publicaciones, fotos y videos reales aparecen solos.

## Funciones

- **Sala de Oración** con 3 niveles de privacidad:
  - 🕊️ **Muro anónimo**: la iglesia ora con un toque ("Estoy orando" enciende una vela). El autor puede marcarla como **respondida** y añadir un testimonio.
  - 🔒 **Solo el pastor**: confidencial, nunca se publica.
  - 🗝️ **Diario cifrado**: AES-256-GCM con clave derivada del PIN (PBKDF2, 250 000 iteraciones). Se guarda solo en el dispositivo del usuario; ni la iglesia puede leerlo.
  - **Orar ahora**: oración guiada de 2 minutos (modelo ACTS) con animación de respiración.
- **Jóvenes**: reto bíblico (quiz) con puntos y racha diaria, reto semanal, preguntas anónimas, playlist y eventos.
- **Mujeres**: devocional diario, programa "Hermana de oración" y calendario de actividades.
- Contador en vivo al próximo culto (hora de Texas) y botón para agregar cada culto al calendario con recordatorio.
- Versículo del día con opción de compartir, tema claro/oscuro, animaciones y diseño adaptado a celulares.

## Activar el servidor de oración

Sin servidor (`prayerApi: null`), el muro funciona en **modo demostración**: cada visitante ve las peticiones de ejemplo más las suyas. Para que el muro se comparta entre todos y las peticiones confidenciales lleguen al pastor, define `prayerApi` con la URL de un pequeño backend que implemente:

| Método | Ruta | Cuerpo / respuesta |
|---|---|---|
| GET | `/wall` | `[{ id, category, text, name, ts, prayers, answered, testimony }]` (solo las públicas y aprobadas; **nunca** devolver `token` ni `contact`) |
| POST | `/requests` | `{ id, privacy: "public"\|"pastor", category, text, name, contact?, ts, token }` |
| POST | `/pray/:id` | Suma 1 a `prayers` |
| POST | `/answer/:id` | `{ testimony, token }`: solo si `token` coincide con el guardado |
| POST | `/questions` | `{ q }`: preguntas anónimas de jóvenes |
| POST | `/sisters` | `{ name }`: inscripciones a Hermana de oración |

Recomendaciones: moderar las peticiones públicas antes de mostrarlas, enviar las de `privacy: "pastor"` por correo o a un panel privado, y limitar la frecuencia de envíos por IP. Se puede montar con Supabase, Firebase o Cloudflare Workers + D1.
