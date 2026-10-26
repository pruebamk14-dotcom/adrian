/* ================================================================
   CONFIGURACIÓN DE LA IGLESIA
   Edita este archivo para cambiar horarios, eventos, dirección, etc.
   No hace falta tocar el resto del código.
   ================================================================ */
window.CHURCH = {
  name: "Iglesia Bautista Vida en Cristo",
  facebook: "https://www.facebook.com/vidaencristotexas/",

  // Dirección exacta del templo (para el mapa y el botón "Cómo llegar").
  // CAMBIAR por la dirección real, ej: "1234 Main St, South Houston, TX 77587"
  address: "South Houston, TX",

  // Zona horaria de la iglesia
  timezone: "America/Chicago",

  // Cultos semanales. day: 0=Domingo, 1=Lunes … 6=Sábado. time: "HH:MM" (24h)
  // CONFIRMAR con el pastor y ajustar.
  services: [
    { day: 0, time: "11:00", title: "Culto Dominical",       desc: "Alabanza, oración y la Palabra" },
    { day: 3, time: "19:30", title: "Estudio Bíblico",        desc: "Crecemos juntos en la fe" },
    { day: 5, time: "19:30", title: "Jóvenes",                desc: "Reunión de jóvenes" },
    { day: 6, time: "10:00", title: "Mujeres de Propósito",   desc: "Un sábado al mes" }
  ],

  youthEvents: [
    { date: "2026-11-14", title: "Noche de alabanza y pizza" },
    { date: "2026-11-28", title: "Fogata de acción de gracias" },
    { date: "2026-12-19", title: "Campamento de invierno" }
  ],

  womenEvents: [
    { date: "2026-11-08", title: "Desayuno de Mujeres", desc: "Un tiempo de compañerismo, testimonio y oración.", emoji: "☕" },
    { date: "2026-11-22", title: "Estudio: Mujeres de la Biblia", desc: "Rut, Ester, Débora… mujeres valientes que nos inspiran.", emoji: "📖" },
    { date: "2026-12-13", title: "Taller de manualidades navideñas", desc: "Hacemos regalos para las familias nuevas de la comunidad.", emoji: "🎄" },
    { date: "2027-01-10", title: "Retiro: Renovadas", desc: "Un día para descansar en la presencia de Dios.", emoji: "🌸" }
  ],

  // Fotos de la galería. Coloca las fotos en assets/img/ y agrega aquí sus nombres.
  // Ej: { src: "assets/img/culto1.jpg", caption: "Culto de domingo" }
  gallery: [
    { src: "assets/img/foto1.jpg", caption: "Culto dominical" },
    { src: "assets/img/foto2.jpg", caption: "Alabanza" },
    { src: "assets/img/foto3.jpg", caption: "Bautismos" },
    { src: "assets/img/foto4.jpg", caption: "Comunidad" },
    { src: "assets/img/foto5.jpg", caption: "Niños" },
    { src: "assets/img/foto6.jpg", caption: "Jóvenes" }
  ],

  /* Conexión con un servidor para que las peticiones lleguen al pastor y
     el muro se comparta entre todos los visitantes. Si se deja en null,
     todo se guarda solo en el navegador de cada persona (modo demostración).
     Ver README.md → "Activar el servidor de oración". */
  prayerApi: null,

  // Si no hay servidor, las peticiones "Solo el pastor" abren el correo del
  // visitante dirigido a esta dirección. Ej: "pastor@vidaencristotexas.org"
  pastorEmail: null
};
