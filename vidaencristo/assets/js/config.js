/* ================================================================
   CONFIGURACIÓN DE LA IGLESIA
   Edita este archivo para cambiar horarios, eventos, dirección, etc.
   No hace falta tocar el resto del código.
   ================================================================ */
window.CHURCH = {
  name: "Iglesia Bautista Vida en Cristo",
  facebook: "https://www.facebook.com/vidaencristotexas/",

  // Dirección del templo (para el mapa y el botón "Cómo llegar").
  address: "18131 Nassau Bay Dr, Houston, TX 77058",

  // Zona horaria de la iglesia
  timezone: "America/Chicago",

  // Reuniones. day: 0=Domingo, 1=Lunes … 6=Sábado. time: "HH:MM" (24h)
  // nth: (opcional) para reuniones mensuales, ej. nth: 2 = segundo <día> del mes.
  // group: "jovenes" hace que la reunión aparezca también en la sección de Jóvenes.
  // Agrega aquí otras reuniones fijas (estudio bíblico, jóvenes…) cuando se confirmen.
  services: [
    { day: 0, time: "12:45", title: "Culto Dominical", desc: "En la capilla · Alabanza, oración y la Palabra" },
    { day: 0, nth: 2, time: "13:25", title: "Jóvenes: Camino a la madurez", desc: "Salón #113 · ¡Trae tu Biblia!", group: "jovenes" }
  ],

  // Actividades especiales de jóvenes (las reuniones mensuales salen solas de "services").
  // Ej: { date: "2026-12-19", title: "Campamento de invierno" }
  youthEvents: [],

  womenEvents: [
    { date: "2026-11-08", title: "Desayuno de Mujeres", desc: "Un tiempo de compañerismo, testimonio y oración.", emoji: "☕" },
    { date: "2026-11-22", title: "Estudio: Mujeres de la Biblia", desc: "Rut, Ester, Débora… mujeres valientes que nos inspiran.", emoji: "📖" },
    { date: "2026-12-13", title: "Taller de manualidades navideñas", desc: "Hacemos regalos para las familias nuevas de la comunidad.", emoji: "🎄" },
    { date: "2027-01-10", title: "Retiro: Renovadas", desc: "Un día para descansar en la presencia de Dios.", emoji: "🌸" }
  ],

  // Fotos de la galería. Coloca las fotos en assets/img/ y agrega aquí sus nombres.
  // Ej: { src: "assets/img/culto1.jpg", caption: "Culto de domingo" }
  gallery: [
    { src: "assets/img/alabanza.jpg",    caption: "Alabanza" },
    { src: "assets/img/jovenes-grupo.jpg", caption: "Jóvenes Vida en Cristo" },
    { src: "assets/img/jovenes.jpg",     caption: "Jóvenes" },
    { src: "assets/img/comunidad.jpg",   caption: "Comunión entre hermanos" },
    { src: "assets/img/familia.jpg",     caption: "Familia de fe" },
    { src: "assets/img/predicacion.jpg", caption: "La Palabra" },
    { src: "assets/img/celebracion.jpg", caption: "Celebrando juntos" },
    { src: "assets/img/servicio.jpg",    caption: "Sirviendo a la comunidad" },
    { src: "assets/img/encuentro.jpg",   caption: "Encuentro con Jesús" },
    { src: "assets/img/coro-ninos.jpg",  caption: "Coro de niños" },
    { src: "assets/img/abrazo.jpg",      caption: "Un abrazo de hermanos" },
    { src: "assets/img/discipulado.jpg", caption: "Creciendo en la fe" },
    { src: "assets/img/predicacion2.jpg", caption: "Predicación" },
    { src: "assets/img/ninos.jpg",       caption: "Los más pequeños" },
    { src: "assets/img/jovenes-grupo2.jpg", caption: "Jóvenes en equipo" }
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
