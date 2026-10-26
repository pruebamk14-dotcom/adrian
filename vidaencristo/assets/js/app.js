/* =========================================================
   Vida en Cristo — app
   ========================================================= */
(() => {
  "use strict";
  const C = window.CHURCH || {};
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- safe storage ---------- */
  const store = {
    get(k, d) { try { const v = localStorage.getItem("vec_" + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
    set(k, v) { try { localStorage.setItem("vec_" + k, JSON.stringify(v)); } catch {} }
  };

  const el = (tag, props = {}, ...kids) => {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === "class") n.className = v;
      else if (k === "text") n.textContent = v;
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v);
    }
    kids.flat().forEach(c => c != null && n.append(c));
    return n;
  };

  let toastTimer;
  const toast = (msg) => {
    const t = $("#toast");
    t.textContent = msg; t.classList.add("show");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove("show"), 3600);
  };

  const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
  const DAYS = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"];
  const parseDate = (s) => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
  const fmt12 = (hhmm) => { let [h, m] = hhmm.split(":").map(Number); const ap = h >= 12 ? "PM" : "AM"; h = h % 12 || 12; return `${h}:${String(m).padStart(2, "0")} ${ap}`; };
  const timeAgo = (ts) => {
    const s = (Date.now() - ts) / 1000;
    if (s < 60) return "hace un momento";
    if (s < 3600) return `hace ${Math.floor(s / 60)} min`;
    if (s < 86400) return `hace ${Math.floor(s / 3600)} h`;
    const d = Math.floor(s / 86400); return d === 1 ? "ayer" : `hace ${d} días`;
  };
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

  /* =========================================================
     Theme, nav, cursor
     ========================================================= */
  const root = document.documentElement;
  const savedTheme = store.get("theme", null);
  if (savedTheme) root.dataset.theme = savedTheme;
  $("#themeToggle").addEventListener("click", () => {
    const isLight = root.dataset.theme === "light";
    root.dataset.theme = isLight ? "dark" : "light";
    store.set("theme", root.dataset.theme);
  });

  const nav = $("#nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 30);
  addEventListener("scroll", onScroll, { passive: true }); onScroll();

  const menuBtn = $("#menuBtn"), navLinks = $("#navLinks");
  menuBtn.addEventListener("click", () => {
    const open = navLinks.classList.toggle("open");
    menuBtn.setAttribute("aria-expanded", open);
  });
  $$("a", navLinks).forEach(a => a.addEventListener("click", () => { navLinks.classList.remove("open"); menuBtn.setAttribute("aria-expanded", false); }));

  const sections = $$("main section[id]");
  const navMap = new Map($$("a[href^='#']", navLinks).map(a => [a.getAttribute("href").slice(1), a]));
  const sectionObs = new IntersectionObserver((entries) => {
    entries.forEach(e => { if (e.isIntersecting) { navMap.forEach(a => a.classList.remove("current")); navMap.get(e.target.id)?.classList.add("current"); } });
  }, { rootMargin: "-45% 0px -50% 0px" });
  sections.forEach(s => sectionObs.observe(s));

  if (!reduced && matchMedia("(pointer: fine)").matches) {
    addEventListener("pointermove", (e) => {
      root.style.setProperty("--mx", e.clientX + "px");
      root.style.setProperty("--my", e.clientY + "px");
    }, { passive: true });
  }

  /* reveal on scroll */
  const revealObs = new IntersectionObserver((entries) => {
    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); revealObs.unobserve(e.target); } });
  }, { threshold: 0.12 });
  const observeReveal = (scope = document) => $$(".reveal:not(.in)", scope).forEach((n, i) => { n.style.transitionDelay = `${Math.min(i % 6, 5) * 70}ms`; revealObs.observe(n); });
  observeReveal();

  /* tilt + spotlight */
  $$(".tilt").forEach(card => {
    if (reduced) return;
    card.addEventListener("pointermove", (e) => {
      const r = card.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
      card.style.transform = `perspective(900px) rotateY(${(x - .5) * 8}deg) rotateX(${(.5 - y) * 8}deg)`;
      card.style.setProperty("--x", x * 100 + "%"); card.style.setProperty("--y", y * 100 + "%");
    });
    card.addEventListener("pointerleave", () => { card.style.transform = ""; });
  });

  /* =========================================================
     Hero canvas — rising particles of light
     ========================================================= */
  (() => {
    const cv = $("#heroCanvas"); if (!cv) return;
    const ctx = cv.getContext("2d");
    let w, h, dpr, parts = [], mouse = { x: -999, y: -999 }, running = true;
    const resize = () => {
      dpr = Math.min(devicePixelRatio || 1, 2);
      w = cv.clientWidth; h = cv.clientHeight;
      cv.width = w * dpr; cv.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const n = Math.round(Math.min(110, w * h / 12000));
      parts = Array.from({ length: n }, () => spawn(true));
    };
    const spawn = (anyY) => ({
      x: Math.random() * w, y: anyY ? Math.random() * h : h + 10,
      r: Math.random() * 1.8 + .4, vy: -(Math.random() * .35 + .1), vx: (Math.random() - .5) * .15,
      a: Math.random() * .6 + .2, tw: Math.random() * Math.PI * 2
    });
    const gold = () => getComputedStyle(root).getPropertyValue("--gold").trim() || "#f5c46b";
    let col = gold();
    new MutationObserver(() => col = gold()).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
    const frame = () => {
      if (!running) return;
      ctx.clearRect(0, 0, w, h);
      // central light beam
      const g = ctx.createRadialGradient(w / 2, h * .38, 0, w / 2, h * .38, Math.max(w, h) * .45);
      g.addColorStop(0, "rgba(245,196,107,.10)"); g.addColorStop(1, "rgba(245,196,107,0)");
      ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        const dx = p.x - mouse.x, dy = p.y - mouse.y, d = Math.hypot(dx, dy);
        if (d < 140) { p.x += dx / d * .8; p.y += dy / d * .8; }
        p.x += p.vx; p.y += p.vy; p.tw += .03;
        if (p.y < -10) parts[i] = spawn(false);
        ctx.globalAlpha = p.a * (.6 + Math.sin(p.tw) * .4);
        ctx.fillStyle = col; ctx.shadowBlur = 10; ctx.shadowColor = col;
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2); ctx.fill();
        for (let j = i + 1; j < parts.length; j++) {
          const q = parts[j], dd = Math.hypot(p.x - q.x, p.y - q.y);
          if (dd < 90) { ctx.globalAlpha = (1 - dd / 90) * .12; ctx.shadowBlur = 0; ctx.strokeStyle = col; ctx.lineWidth = .6; ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(q.x, q.y); ctx.stroke(); }
        }
      }
      ctx.globalAlpha = 1; ctx.shadowBlur = 0;
      requestAnimationFrame(frame);
    };
    resize(); addEventListener("resize", resize);
    cv.parentElement.addEventListener("pointermove", (e) => { const r = cv.getBoundingClientRect(); mouse = { x: e.clientX - r.left, y: e.clientY - r.top }; });
    cv.parentElement.addEventListener("pointerleave", () => mouse = { x: -999, y: -999 });
    new IntersectionObserver(([e]) => { const was = running; running = e.isIntersecting; if (running && !was) requestAnimationFrame(frame); }).observe(cv);
    if (reduced) { running = false; frame(); } else requestAnimationFrame(frame);
  })();

  /* =========================================================
     Services: countdown + schedule
     ========================================================= */
  const services = (C.services || []).slice();
  const nowInTz = () => new Date(new Date().toLocaleString("en-US", { timeZone: C.timezone || "America/Chicago" }));

  const ORD = ["", "1er", "2º", "3er", "4º", "5º"];
  const dayLabel = (s) => s.nth ? `${ORD[s.nth]} ${DAYS[s.day].toLowerCase()} del mes` : DAYS[s.day];
  const matches = (s, d) => d.getDay() === s.day && (!s.nth || Math.ceil(d.getDate() / 7) === s.nth);
  // Próximas fechas de una reunión (semanal o mensual), incluyendo la que esté en curso
  const occurrences = (s, from, count = 1) => {
    const [h, m] = s.time.split(":").map(Number), out = [];
    for (let add = 0; add <= 400 && out.length < count; add++) {
      const d = new Date(from); d.setDate(from.getDate() + add); d.setHours(h, m, 0, 0);
      if (matches(s, d) && (d > from || from - d < 90 * 60000)) out.push(d);
    }
    return out;
  };
  const nextService = () => {
    const now = nowInTz();
    let best = null;
    for (const s of services) {
      const [d] = occurrences(s, now);
      if (d && (!best || d < best.at)) best = { s, at: d, live: now >= d };
    }
    return best ? { ...best, now } : null;
  };

  const renderSchedule = () => {
    const box = $("#schedule"); if (!box) return;
    const nx = nextService();
    box.replaceChildren(...services.map(s => {
      const card = el("article", { class: "svc reveal" + (nx && nx.s === s ? " next" : "") },
        el("div", { class: "day", text: dayLabel(s) }),
        el("div", { class: "time", text: fmt12(s.time) }),
        el("h3", { text: s.title }),
        el("p", { text: s.desc }),
        el("button", { class: "ics", text: "＋ Agregar a mi calendario", onclick: () => downloadIcs(s) })
      );
      return card;
    }));
    observeReveal(box);
  };

  const downloadIcs = (s) => {
    const [nx] = occurrences(s, nowInTz()); const [h, m] = s.time.split(":").map(Number);
    const p = (n) => String(n).padStart(2, "0");
    const dt = `${nx.getFullYear()}${p(nx.getMonth() + 1)}${p(nx.getDate())}T${p(h)}${p(m)}00`;
    const end = `${nx.getFullYear()}${p(nx.getMonth() + 1)}${p(nx.getDate())}T${p((h + 1) % 24)}${p(m)}30`;
    const byday = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][s.day];
    const ics = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//VidaEnCristo//ES", "BEGIN:VEVENT",
      `UID:${uid()}@vidaencristo`, `DTSTART;TZID=${C.timezone}:${dt}`, `DTEND;TZID=${C.timezone}:${end}`,
      s.nth ? `RRULE:FREQ=MONTHLY;BYDAY=${s.nth}${byday}` : `RRULE:FREQ=WEEKLY;BYDAY=${byday}`, `SUMMARY:${s.title} · Vida en Cristo`, `LOCATION:${C.address}`,
      "BEGIN:VALARM", "TRIGGER:-PT60M", "ACTION:DISPLAY", "DESCRIPTION:Recordatorio", "END:VALARM",
      "END:VEVENT", "END:VCALENDAR"].join("\r\n");
    const a = el("a", { href: URL.createObjectURL(new Blob([ics], { type: "text/calendar" })), download: "vida-en-cristo.ics" });
    a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    toast(s.nth ? "📅 Evento mensual descargado con recordatorio" : "📅 Evento semanal descargado con recordatorio");
  };

  const tickCountdown = () => {
    const nx = nextService(); if (!nx) { $("#countdown").hidden = true; return; }
    const cd = $("#countdown");
    if (nx.live) {
      cd.classList.add("is-live");
      $("#cdTitle").textContent = "¡En vivo ahora!";
      ["#cdD", "#cdH", "#cdM", "#cdS"].forEach(id => $(id).textContent = "0");
      $("#cdWhen").textContent = `${nx.s.title} · Míralo en Facebook`;
      return;
    }
    cd.classList.remove("is-live");
    let ms = nx.at - nx.now;
    const d = Math.floor(ms / 864e5); ms -= d * 864e5;
    const hh = Math.floor(ms / 36e5); ms -= hh * 36e5;
    const mm = Math.floor(ms / 6e4); ms -= mm * 6e4;
    const ss = Math.floor(ms / 1000);
    $("#cdTitle").textContent = `Próximo: ${nx.s.title}`;
    $("#cdD").textContent = d; $("#cdH").textContent = String(hh).padStart(2, "0");
    $("#cdM").textContent = String(mm).padStart(2, "0"); $("#cdS").textContent = String(ss).padStart(2, "0");
    $("#cdWhen").textContent = `${nx.at.toLocaleDateString("es-US", { weekday: "long", day: "numeric", month: "long" })} · ${fmt12(nx.s.time)} (hora de Texas)`;
  };
  renderSchedule(); tickCountdown(); setInterval(tickCountdown, 1000);

  /* =========================================================
     Verse of the day
     ========================================================= */
  const VERSES = [
    ["Porque de tal manera amó Dios al mundo, que ha dado a su Hijo unigénito, para que todo aquel que en él cree, no se pierda, mas tenga vida eterna.", "Juan 3:16"],
    ["Todo lo puedo en Cristo que me fortalece.", "Filipenses 4:13"],
    ["Jehová es mi pastor; nada me faltará.", "Salmo 23:1"],
    ["Mas buscad primeramente el reino de Dios y su justicia, y todas estas cosas os serán añadidas.", "Mateo 6:33"],
    ["Fíate de Jehová de todo tu corazón, y no te apoyes en tu propia prudencia.", "Proverbios 3:5"],
    ["Venid a mí todos los que estáis trabajados y cargados, y yo os haré descansar.", "Mateo 11:28"],
    ["De modo que si alguno está en Cristo, nueva criatura es; las cosas viejas pasaron; he aquí todas son hechas nuevas.", "2 Corintios 5:17"],
    ["Por nada estéis afanosos, sino sean conocidas vuestras peticiones delante de Dios en toda oración y ruego, con acción de gracias.", "Filipenses 4:6"],
    ["Mira que te mando que te esfuerces y seas valiente; no temas ni desmayes, porque Jehová tu Dios estará contigo dondequiera que vayas.", "Josué 1:9"],
    ["El ladrón no viene sino para hurtar y matar y destruir; yo he venido para que tengan vida, y para que la tengan en abundancia.", "Juan 10:10"],
    ["Y sabemos que a los que aman a Dios, todas las cosas les ayudan a bien.", "Romanos 8:28"],
    ["Clama a mí, y yo te responderé, y te enseñaré cosas grandes y ocultas que tú no conoces.", "Jeremías 33:3"],
    ["Pero los que esperan a Jehová tendrán nuevas fuerzas; levantarán alas como las águilas.", "Isaías 40:31"],
    ["Lámpara es a mis pies tu palabra, y lumbrera a mi camino.", "Salmo 119:105"],
    ["Echando toda vuestra ansiedad sobre él, porque él tiene cuidado de vosotros.", "1 Pedro 5:7"]
  ];
  const dayIndex = Math.floor(Date.now() / 864e5);
  let vIdx = dayIndex % VERSES.length;
  const showVerse = () => {
    const q = $("#verseText"); q.style.opacity = 0;
    setTimeout(() => { q.textContent = `“${VERSES[vIdx][0]}”`; $("#verseRef").textContent = VERSES[vIdx][1]; q.style.opacity = 1; }, 250);
  };
  showVerse();
  $("#verseNext").addEventListener("click", () => { vIdx = (vIdx + 1) % VERSES.length; showVerse(); });
  $("#verseShare").addEventListener("click", async () => {
    const text = `“${VERSES[vIdx][0]}” — ${VERSES[vIdx][1]}\n\nIglesia Bautista Vida en Cristo`;
    try {
      if (navigator.share) await navigator.share({ text, url: location.href });
      else { await navigator.clipboard.writeText(text); toast("Versículo copiado ✨"); }
    } catch {}
  });

  /* =========================================================
     Prayer API adapter (local demo or remote server)
     ========================================================= */
  const API = C.prayerApi;
  const SEED = [
    { id: "s1", category: "salud", text: "Por la salud de mi mamá, que tiene una operación la próxima semana. Que Dios guíe las manos de los médicos.", ts: Date.now() - 36e5 * 5, prayers: 14, sample: true },
    { id: "s2", category: "trabajo", text: "Llevo meses buscando trabajo. Oren para que el Señor abra una puerta y me dé paciencia.", ts: Date.now() - 864e5 * 1.2, prayers: 9, sample: true },
    { id: "s3", category: "familia", text: "Por mi hijo adolescente, que se ha alejado de Dios. Que vuelva al camino.", ts: Date.now() - 864e5 * 2, prayers: 21, sample: true },
    { id: "s4", category: "fe", text: "Por la fe de mi familia y por nuestros papeles migratorios.", ts: Date.now() - 864e5 * 6, prayers: 33, answered: true, testimony: "¡Dios respondió! Nos aprobaron todo. Gracias por orar.", sample: true }
  ];
  const prayerApi = {
    async list() {
      if (API) { try { const r = await fetch(API + "/wall"); if (r.ok) return await r.json(); } catch {} }
      return store.get("wall", null) || SEED;
    },
    async create(req) {
      if (API) {
        const r = await fetch(API + "/requests", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(req) });
        if (!r.ok) throw new Error("server");
        return await r.json().catch(() => req);
      }
      if (req.privacy === "public") { const w = await this.list(); w.unshift(req); store.set("wall", w); }
      else { const box = store.get("outbox", []); box.push(req); store.set("outbox", box); }
      return req;
    },
    async pray(id) {
      if (API) { fetch(API + "/pray/" + encodeURIComponent(id), { method: "POST" }).catch(() => {}); }
      const w = await this.list(); const r = w.find(x => x.id === id); if (r) { r.prayers = (r.prayers || 0) + 1; if (!API) store.set("wall", w); }
    },
    async answer(id, testimony, token) {
      if (API) { await fetch(API + "/answer/" + encodeURIComponent(id), { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ testimony, token }) }).catch(() => {}); }
      const w = await this.list(); const r = w.find(x => x.id === id); if (r) { r.answered = true; r.testimony = testimony; if (!API) store.set("wall", w); }
    },
    async send(kind, payload) {
      if (API) { try { await fetch(API + "/" + kind, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }); return; } catch {} }
      const box = store.get(kind, []); box.push({ ...payload, ts: Date.now() }); store.set(kind, box);
    }
  };

  /* ---------- Tabs ---------- */
  const tabs = $$(".tab"), ink = $(".tab-ink");
  const moveInk = (t) => { ink.style.left = t.offsetLeft + "px"; ink.style.width = t.offsetWidth + "px"; };
  const selectTab = (t) => {
    tabs.forEach(x => { const on = x === t; x.classList.toggle("active", on); x.setAttribute("aria-selected", on); const p = $("#" + x.getAttribute("aria-controls")); p.hidden = !on; p.classList.toggle("active", on); });
    moveInk(t);
  };
  tabs.forEach(t => t.addEventListener("click", () => selectTab(t)));
  $(".tabs").addEventListener("keydown", (e) => {
    const i = tabs.indexOf(document.activeElement); if (i < 0) return;
    if (e.key === "ArrowRight" || e.key === "ArrowLeft") { const n = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length]; n.focus(); selectTab(n); }
  });
  addEventListener("resize", () => moveInk($(".tab.active")));
  requestAnimationFrame(() => moveInk($(".tab.active")));
  document.fonts?.ready.then(() => moveInk($(".tab.active")));

  /* ---------- Wall ---------- */
  const prayed = new Set(store.get("prayed", []));
  const mine = store.get("mine", {}); // id -> token
  let wallFilter = "all";
  const CAT = { salud: "Salud", familia: "Familia", trabajo: "Trabajo", fe: "Fe" };

  const sparks = (x, y) => {
    if (reduced) return;
    for (let i = 0; i < 14; i++) {
      const s = el("span", { class: "spark" }); document.body.append(s);
      const a = Math.random() * Math.PI * 2, d = 30 + Math.random() * 50;
      s.animate([{ transform: `translate(${x}px, ${y}px) scale(1)`, opacity: 1 },
        { transform: `translate(${x + Math.cos(a) * d}px, ${y + Math.sin(a) * d - 40}px) scale(0)`, opacity: 0 }],
        { duration: 800 + Math.random() * 400, easing: "cubic-bezier(.2,.8,.2,1)" }).onfinish = () => s.remove();
      s.style.left = s.style.top = "0";
    }
  };

  const countUp = (node, to) => {
    const from = +node.textContent || 0; if (reduced || from === to) { node.textContent = to; return; }
    const t0 = performance.now();
    const step = (t) => { const k = Math.min(1, (t - t0) / 900); node.textContent = Math.round(from + (to - from) * (1 - Math.pow(1 - k, 3))); if (k < 1) requestAnimationFrame(step); };
    requestAnimationFrame(step);
  };

  const renderWall = async () => {
    const all = await prayerApi.list();
    countUp($("#statReq"), all.length);
    countUp($("#statPray"), all.reduce((s, r) => s + (r.prayers || 0), 0));
    countUp($("#statAns"), all.filter(r => r.answered).length);
    const list = all.filter(r => wallFilter === "all" ? true : wallFilter === "respondida" ? r.answered : r.category === wallFilter);
    const wall = $("#wall");
    if (!list.length) { wall.replaceChildren(el("p", { class: "small", text: "No hay peticiones en esta categoría todavía." })); return; }
    wall.replaceChildren(...list.map((r, i) => {
      const isPrayed = prayed.has(r.id);
      const btn = el("button", { class: "pray-btn" + (isPrayed ? " prayed" : ""), "aria-pressed": isPrayed },
        el("span", { class: "candle", "aria-hidden": "true" }),
        el("span", { text: isPrayed ? `Oré por esto · ${r.prayers || 0}` : `Estoy orando · ${r.prayers || 0}` }));
      btn.addEventListener("click", async (e) => {
        if (prayed.has(r.id)) return;
        prayed.add(r.id); store.set("prayed", [...prayed]);
        sparks(e.clientX, e.clientY);
        await prayerApi.pray(r.id); renderWall();
        toast("🕯️ Gracias por orar. Tu vela está encendida.");
      });
      const card = el("article", { class: "pcard" + (r.answered ? " answered" : "") },
        el("div", { class: "meta" }, el("span", { class: "cat", text: (r.answered ? "✨ Respondida · " : "") + (CAT[r.category] || "Oración") }), el("span", { text: r.sample ? "ejemplo" : timeAgo(r.ts) })),
        el("p", { text: r.text }),
        r.testimony ? el("div", { class: "testimony", text: "Testimonio: " + r.testimony }) : null,
        el("div", { class: "who", text: r.name ? `— ${r.name}` : "— Anónimo" }),
        el("div", { style: "margin-top:.8rem;display:flex;gap:.4rem;flex-wrap:wrap" }, btn,
          mine[r.id] && !r.answered ? el("button", { class: "chip", text: "✨ Dios respondió", onclick: async () => {
            const t = prompt("¡Gloria a Dios! Cuéntanos brevemente cómo respondió (opcional):") ?? null;
            if (t === null) return;
            await prayerApi.answer(r.id, t.trim().slice(0, 300) || "¡Dios respondió esta oración!", mine[r.id]);
            renderWall(); toast("🙌 ¡Gracias por compartir tu testimonio!");
          } }) : null)
      );
      card.style.animationDelay = `${Math.min(i, 8) * 50}ms`;
      return card;
    }));
  };
  $$(".wall-filters .chip").forEach(c => c.addEventListener("click", () => {
    $$(".wall-filters .chip").forEach(x => x.classList.toggle("active", x === c));
    wallFilter = c.dataset.filter; renderWall();
  }));
  renderWall();

  /* ---------- Encrypted journal (AES-GCM + PBKDF2, never leaves the device) ---------- */
  const enc = new TextEncoder(), dec = new TextDecoder();
  const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
  const unb64 = (s) => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const deriveKey = async (pin, salt) => {
    const base = await crypto.subtle.importKey("raw", enc.encode(pin), "PBKDF2", false, ["deriveKey"]);
    return crypto.subtle.deriveKey({ name: "PBKDF2", salt, iterations: 250000, hash: "SHA-256" }, base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  };
  const seal = async (key, obj) => { const iv = crypto.getRandomValues(new Uint8Array(12)); const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(JSON.stringify(obj))); return { iv: b64(iv), ct: b64(ct) }; };
  const open = async (key, box) => JSON.parse(dec.decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(box.iv) }, key, unb64(box.ct))));

  const journal = {
    key: null, entries: [],
    data() { return store.get("journal", null); },
    async unlock(pin) {
      let d = this.data();
      if (!d) {
        const salt = crypto.getRandomValues(new Uint8Array(16));
        const key = await deriveKey(pin, salt);
        d = { salt: b64(salt), check: await seal(key, "ok"), items: [] };
        store.set("journal", d); this.key = key; this.entries = []; return true;
      }
      const key = await deriveKey(pin, unb64(d.salt));
      try { await open(key, d.check); } catch { return false; }
      this.key = key; this.entries = await Promise.all(d.items.map(b => open(key, b)));
      return true;
    },
    async save() { const d = this.data(); d.items = await Promise.all(this.entries.map(e => seal(this.key, e))); store.set("journal", d); },
    async add(entry) { this.entries.unshift(entry); await this.save(); },
    lock() { this.key = null; this.entries = []; }
  };

  const renderJournal = () => {
    const list = $("#journalList");
    $("#journalCount").textContent = `· ${journal.entries.length} oraciones`;
    if (!journal.entries.length) { list.replaceChildren(el("p", { class: "small", text: "Tu diario está vacío. Escribe tu primera oración en «Nueva petición» y elige «Mi diario»." })); return; }
    list.replaceChildren(...journal.entries.map((e, i) => el("div", { class: "jentry" + (e.answered ? " answered" : "") },
      el("div", { class: "meta" }, el("span", { text: (e.answered ? "✨ Respondida · " : "") + (CAT[e.category] || "") }), el("span", { text: new Date(e.ts).toLocaleDateString("es-US", { day: "numeric", month: "short", year: "numeric" }) })),
      el("p", { text: e.text }),
      el("div", { class: "row" },
        el("button", { class: "chip", text: e.answered ? "Marcar pendiente" : "✨ Respondida", onclick: async () => { e.answered = !e.answered; await journal.save(); renderJournal(); } }),
        el("button", { class: "chip", text: "Borrar", onclick: async () => { if (!confirm("¿Borrar esta oración?")) return; journal.entries.splice(i, 1); await journal.save(); renderJournal(); } })
      ))));
  };
  const showJournal = (openState) => { $("#journalLocked").hidden = openState; $("#journalOpen").hidden = !openState; if (openState) renderJournal(); };
  const updateUnlockCopy = () => { $("#unlockForm button").textContent = journal.data() ? "Abrir" : "Crear diario"; };
  updateUnlockCopy();
  $("#unlockForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const inp = $("input", e.target), pin = inp.value.trim();
    if (pin.length < 4) { $("#unlockErr").textContent = "El PIN debe tener al menos 4 caracteres."; return; }
    if (!crypto.subtle) { $("#unlockErr").textContent = "Tu navegador no permite cifrado. Abre el sitio con https://"; return; }
    const ok = await journal.unlock(pin); inp.value = "";
    if (!ok) { $("#unlockErr").textContent = "PIN incorrecto."; $("#journalLocked").animate([{ transform: "translateX(-6px)" }, { transform: "translateX(6px)" }, { transform: "none" }], 300); return; }
    $("#unlockErr").textContent = ""; showJournal(true);
  });
  $("#lockBtn").addEventListener("click", () => { journal.lock(); updateUnlockCopy(); showJournal(false); toast("🔒 Diario cerrado"); });

  /* ---------- New request form ---------- */
  const form = $("#prayerForm");
  const NOTES = {
    public: "🕊️ Se publicará sin tu nombre (a menos que lo escribas). La iglesia podrá orar contigo.",
    pastor: "🔒 Solo el equipo pastoral la leerá. No se publica en ningún lugar.",
    journal: "🗝️ Se cifra en este dispositivo con tu PIN. Nadie más puede leerla, ni siquiera la iglesia."
  };
  const syncPrivacy = () => {
    const v = form.privacy.value;
    $("#privacyNote").textContent = NOTES[v];
    $("#nameField").hidden = v === "journal";
    $("#contactField").hidden = v !== "pastor";
    $("#pinField").hidden = v !== "journal";
    form.pin.required = v === "journal";
    $("#nameField span").textContent = v === "pastor" ? "Tu nombre (opcional)" : "Firma (opcional, ej. «Una hermana»)";
  };
  $$("input[name=privacy]", form).forEach(r => r.addEventListener("change", syncPrivacy)); syncPrivacy();
  form.text.addEventListener("input", () => $("#charCount").textContent = form.text.value.length);

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const v = form.privacy.value, text = form.text.value.trim();
    if (text.length < 5) { toast("Escribe un poco más sobre tu petición 🙏"); return; }
    const btn = $("button[type=submit]", form); btn.disabled = true;
    try {
      if (v === "journal") {
        const pin = form.pin.value.trim();
        if (pin.length < 4) { toast("El PIN debe tener al menos 4 caracteres"); return; }
        if (!journal.key) { const ok = await journal.unlock(pin); if (!ok) { toast("PIN incorrecto para tu diario"); return; } }
        await journal.add({ text, category: form.category.value, ts: Date.now() });
        toast("🗝️ Guardada y cifrada en tu diario");
        selectTab($("#t-journal")); showJournal(true);
      } else {
        const req = { id: uid(), privacy: v, category: form.category.value, text, name: form.name.value.trim().slice(0, 40) || "", ts: Date.now(), prayers: 0 };
        if (v === "pastor") req.contact = form.contact.value.trim().slice(0, 80);
        const token = uid(); req.token = token;
        await prayerApi.create(req);
        if (v === "public") {
          mine[req.id] = token; store.set("mine", mine);
          toast("🕊️ Tu petición está en el muro. ¡Estamos orando contigo!");
          selectTab($("#t-wall")); renderWall();
        } else {
          if (!API && C.pastorEmail) {
            const body = `Petición de oración (${CAT[req.category]}):\n\n${text}\n\n${req.name ? "De: " + req.name : "Anónimo"}${req.contact ? "\nContacto: " + req.contact : ""}`;
            location.href = `mailto:${C.pastorEmail}?subject=${encodeURIComponent("Petición de oración confidencial")}&body=${encodeURIComponent(body)}`;
          }
          toast("🔒 Tu petición confidencial fue enviada al pastor. Dios te bendiga.");
        }
      }
      form.reset(); syncPrivacy(); $("#charCount").textContent = 0;
    } catch {
      toast("No se pudo enviar. Revisa tu conexión e intenta de nuevo.");
    } finally { btn.disabled = false; }
  });

  /* ---------- Guided prayer (ACTS) ---------- */
  const STEPS = [
    { t: "Respira y adora", s: "Adoración", x: "Toma un momento para reconocer quién es Dios. Inhala despacio… exhala. Él está aquí contigo.", v: "“Estad quietos, y conoced que yo soy Dios.” — Salmo 46:10" },
    { t: "Abre tu corazón", s: "Confesión", x: "Habla con Dios con honestidad. Entrégale aquello que te pesa. Él es fiel para perdonar.", v: "“Si confesamos nuestros pecados, él es fiel y justo para perdonar.” — 1 Juan 1:9" },
    { t: "Da gracias", s: "Gratitud", x: "Piensa en tres cosas por las que estás agradecido hoy, y díselas a Dios una por una.", v: "“Dad gracias en todo, porque esta es la voluntad de Dios.” — 1 Tesalonicenses 5:18" },
    { t: "Presenta tus peticiones", s: "Súplica", x: "Ora por tu familia, por tu iglesia, por tu ciudad y por lo que necesitas. Él te escucha.", v: "“Pedid, y se os dará; buscad, y hallaréis.” — Mateo 7:7" }
  ];
  const STEP_SEC = 30;
  let gI = 0, gTimer = null, gElapsed = 0, breathTimer = null;
  const gRender = () => {
    const s = STEPS[gI];
    $("#gStep").textContent = `Paso ${gI + 1} de ${STEPS.length} · ${s.s}`;
    $("#gTitle").textContent = s.t; $("#gText").textContent = s.x; $("#gVerse").textContent = s.v;
    $("#gPrev").disabled = gI === 0; $("#gNext").disabled = gI === STEPS.length - 1;
  };
  const gStop = () => { clearInterval(gTimer); clearInterval(breathTimer); gTimer = null; $("#breath").classList.remove("inhale"); $("#gStart").textContent = "Comenzar · 2 min"; };
  $("#gStart").addEventListener("click", () => {
    if (gTimer) { gStop(); return; }
    gElapsed = gI * STEP_SEC; $("#gStart").textContent = "Pausar";
    const b = $("#breath"); b.classList.add("inhale");
    breathTimer = setInterval(() => b.classList.toggle("inhale"), 4000);
    gTimer = setInterval(() => {
      gElapsed++;
      $("#gBar").style.width = (gElapsed / (STEP_SEC * STEPS.length)) * 100 + "%";
      const idx = Math.floor(gElapsed / STEP_SEC);
      if (idx >= STEPS.length) { gStop(); $("#gTitle").textContent = "Amén 🙏"; $("#gText").textContent = "Gracias por tomar este tiempo con Dios. Lleva su paz contigo hoy."; return; }
      if (idx !== gI) { gI = idx; gRender(); }
    }, 1000);
  });
  $("#gPrev").addEventListener("click", () => { if (gI > 0) { gI--; gElapsed = gI * STEP_SEC; gRender(); } });
  $("#gNext").addEventListener("click", () => { if (gI < STEPS.length - 1) { gI++; gElapsed = gI * STEP_SEC; gRender(); } });
  gRender();

  /* =========================================================
     Youth
     ========================================================= */
  const QUIZ = [
    ["¿Quién construyó el arca?", ["Moisés", "Noé", "Abraham", "David"], 1],
    ["¿Cuántos discípulos tuvo Jesús?", ["7", "10", "12", "40"], 2],
    ["¿Con qué venció David a Goliat?", ["Una espada", "Una lanza", "Una honda y una piedra", "Sus manos"], 2],
    ["¿Cuál es el primer libro de la Biblia?", ["Éxodo", "Génesis", "Mateo", "Salmos"], 1],
    ["¿En qué ciudad nació Jesús?", ["Nazaret", "Jerusalén", "Belén", "Capernaum"], 2],
    ["¿Quién negó a Jesús tres veces?", ["Judas", "Juan", "Pedro", "Tomás"], 2],
    ["¿Cuántos días estuvo Jonás en el gran pez?", ["1", "3", "7", "40"], 1],
    ["¿Qué mar abrió Dios para Moisés?", ["Mar Muerto", "Mar Rojo", "Mar de Galilea", "Mediterráneo"], 1],
    ["¿Quién fue arrojado al foso de los leones?", ["Daniel", "José", "Elías", "Sansón"], 0],
    ["¿Cuál es el libro más largo de la Biblia?", ["Isaías", "Génesis", "Salmos", "Jeremías"], 2],
    ["¿Qué apóstol escribió más cartas del Nuevo Testamento?", ["Pedro", "Pablo", "Juan", "Santiago"], 1],
    ["¿Cuál fue el primer milagro de Jesús?", ["Caminar sobre el agua", "Agua en vino", "Multiplicar panes", "Sanar a un ciego"], 1],
    ["¿Quién fue la reina que salvó a su pueblo?", ["Rut", "Débora", "Ester", "Raquel"], 2],
    ["¿Cuántos libros tiene la Biblia (protestante)?", ["66", "73", "39", "27"], 0],
    ["¿Quién era el hermano de Moisés?", ["Aarón", "Josué", "Caleb", "Leví"], 0],
    ["¿Qué significa «Emanuel»?", ["Rey de reyes", "Dios con nosotros", "Salvador", "Príncipe de paz"], 1],
    ["¿Quién bautizó a Jesús?", ["Pedro", "Juan el Bautista", "Pablo", "Andrés"], 1],
    ["¿Cuál es el fruto del Espíritu que va primero en Gálatas 5:22?", ["Gozo", "Paz", "Amor", "Fe"], 2]
  ];
  const today = new Date().toISOString().slice(0, 10);
  const streakData = store.get("streak", { last: null, n: 0 });
  $("#streak").textContent = streakData.n;
  $("#qBest").textContent = store.get("best", 0);
  let round = [], qi = 0, score = 0;
  const shuffle = (a) => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const quizStart = () => {
    round = shuffle(QUIZ).slice(0, 5); qi = 0; score = 0; $("#qScore").textContent = 0;
    $("#quiz").replaceChildren(
      el("p", { class: "q-count", id: "qCount" }), el("h3", { id: "qText" }), el("div", { class: "q-opts", id: "qOpts" }),
      el("div", { class: "q-foot" }, el("span", {}, "Puntos: ", el("b", { id: "qScore", text: "0" })), el("span", {}, "Mejor: ", el("b", { id: "qBest", text: store.get("best", 0) })))
    );
    quizShow();
  };
  const quizShow = () => {
    const [q, opts, ans] = round[qi];
    $("#qCount").textContent = `Pregunta ${qi + 1}/${round.length}`;
    $("#qText").textContent = q;
    $("#qOpts").replaceChildren(...opts.map((o, i) => el("button", { class: "q-opt", text: o, onclick: (e) => {
      $$(".q-opt").forEach(b => b.disabled = true);
      const right = i === ans;
      e.currentTarget.classList.add(right ? "right" : "wrong");
      $$(".q-opt")[ans].classList.add("right");
      if (right) { score += 100; $("#qScore").textContent = score; sparks(e.clientX, e.clientY); }
      setTimeout(() => { qi++; qi < round.length ? quizShow() : quizEnd(); }, 1100);
    } })));
  };
  const quizEnd = () => {
    const best = Math.max(store.get("best", 0), score); store.set("best", best);
    if (streakData.last !== today) {
      const y = new Date(Date.now() - 864e5).toISOString().slice(0, 10);
      streakData.n = streakData.last === y ? streakData.n + 1 : 1; streakData.last = today; store.set("streak", streakData);
      $("#streak").textContent = streakData.n;
    }
    const msg = score === 500 ? "¡Perfecto! Eres un experto en la Palabra 🔥" : score >= 300 ? "¡Muy bien! Sigue leyendo tu Biblia 📖" : "¡Buen intento! Mañana hay un nuevo reto 💪";
    $("#quiz").replaceChildren(el("div", { class: "q-done" },
      el("div", { class: "big", text: score }), el("p", { text: msg }),
      el("p", { class: "small", text: `Racha: ${streakData.n} día(s) · Mejor puntuación: ${best}` }),
      el("button", { class: "btn btn-neon", text: "Jugar otra vez", onclick: quizStart })));
  };
  quizStart();

  // weekly challenge
  const CHALLENGES = [
    "Lee un capítulo de Proverbios cada día.",
    "Ora 5 minutos antes de agarrar el celular por la mañana.",
    "Escribe un versículo en una nota y compártelo con un amigo.",
    "Haz algo bueno por alguien sin que lo sepa.",
    "Memoriza Filipenses 4:13 esta semana.",
    "Una semana sin quejarte: cambia cada queja por un «gracias»."
  ];
  const weekNo = Math.floor((Date.now() / 864e5 + 4) / 7);
  $("#challengeText").textContent = CHALLENGES[weekNo % CHALLENGES.length];
  const chKey = "challenge_" + weekNo;
  const chState = store.get(chKey, Array(7).fill(false));
  $("#challengeChecks").replaceChildren(...["D", "L", "M", "M", "J", "V", "S"].map((d, i) => {
    const b = el("button", { class: "check" + (chState[i] ? " on" : ""), text: d, "aria-label": DAYS[i], "aria-pressed": chState[i] });
    b.addEventListener("click", (e) => {
      chState[i] = !chState[i]; store.set(chKey, chState);
      b.classList.toggle("on", chState[i]); b.setAttribute("aria-pressed", chState[i]);
      if (chState[i]) sparks(e.clientX, e.clientY);
      if (chState.every(Boolean)) toast("🏆 ¡Completaste el reto de la semana!");
    });
    return b;
  }));

  // anonymous question
  $("#askForm").addEventListener("submit", async (e) => {
    e.preventDefault(); const inp = $("input", e.target); const q = inp.value.trim(); if (!q) return;
    await prayerApi.send("questions", { q }); inp.value = "";
    $("#askOk").textContent = "✅ ¡Recibida! La responderemos en la próxima reunión.";
    setTimeout(() => $("#askOk").textContent = "", 5000);
  });

  // youth events
  const upcoming = (arr) => arr.filter(e => parseDate(e.date) >= new Date(new Date().toDateString())).sort((a, b) => parseDate(a.date) - parseDate(b.date));
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const recurring = services.filter(s => s.group === "jovenes").flatMap(s => occurrences(s, nowInTz(), 3).map(d => ({ date: iso(d), title: `${s.title} · ${fmt12(s.time)}` })));
  const ye = upcoming([...recurring, ...(C.youthEvents || [])]);
  $("#youthEvents").replaceChildren(...(ye.length ? ye.slice(0, 3).map(ev => { const d = parseDate(ev.date);
    return el("li", {}, el("div", { class: "d" }, el("span", {}, String(d.getDate()), el("small", { text: MONTHS[d.getMonth()] }))), el("b", { text: ev.title })); })
    : [el("li", { class: "small", text: "Pronto anunciaremos nuevas actividades." })]));

  /* =========================================================
     Women
     ========================================================= */
  const DEVOS = [
    ["Vestida de fuerza", "Fuerza y honor son su vestidura; y se ríe de lo por venir.", "Proverbios 31:25", "La mujer que confía en Dios no vive con miedo al mañana. Hoy, vístete de su fuerza y deja que su paz te sostenga."],
    ["Donde tú vayas", "Tu pueblo será mi pueblo, y tu Dios mi Dios.", "Rut 1:16", "Rut eligió la fidelidad cuando todo era incierto. Dios honró su decisión y escribió una historia de redención."],
    ["Para esta hora", "¿Y quién sabe si para esta hora has llegado al reino?", "Ester 4:14", "Estás donde estás con un propósito. Dios puede usar tu vida para bendecir a tu familia y tu comunidad."],
    ["Ella creyó", "Y bienaventurada la que creyó, porque se cumplirá lo que le fue dicho de parte del Señor.", "Lucas 1:45", "Como María, recibe las promesas de Dios con fe. Lo que Él dijo, lo cumplirá."],
    ["Escogió la mejor parte", "María ha escogido la buena parte, la cual no le será quitada.", "Lucas 10:42", "En medio de tantas tareas, sentarte a los pies de Jesús nunca es tiempo perdido."]
  ];
  const dv = DEVOS[dayIndex % DEVOS.length];
  $("#devoTitle").textContent = dv[0];
  $("#devoText").textContent = `“${dv[1]}” ${dv[3]}`;
  $("#devoRef").textContent = dv[2];

  const we = upcoming(C.womenEvents || []);
  $("#womenEvents").replaceChildren(...(we.length ? we.map(ev => { const d = parseDate(ev.date);
    return el("article", { class: "w-card reveal" },
      el("div", { class: "w-date" }, el("div", {}, el("b", { text: String(d.getDate()) }), el("small", { text: MONTHS[d.getMonth()] }))),
      el("div", {}, el("h4", { text: `${ev.emoji || ""} ${ev.title}` }), el("p", { text: ev.desc || "" })));
  }) : [el("p", { class: "small", text: "Pronto anunciaremos nuevas actividades." })]));
  observeReveal($("#womenEvents"));

  $("#sisterForm").addEventListener("submit", async (e) => {
    e.preventDefault(); const inp = $("input", e.target); const name = inp.value.trim(); if (!name) return;
    await prayerApi.send("sisters", { name }); inp.value = "";
    $("#sisterOk").textContent = `💗 ¡Gracias, ${name}! Te asignaremos tu hermana de oración este domingo.`;
  });

  if (!reduced) {
    const petals = $(".petals");
    for (let i = 0; i < 14; i++) {
      const p = el("span", { class: "petal" });
      p.style.left = Math.random() * 100 + "%";
      p.style.animationDuration = 10 + Math.random() * 12 + "s";
      p.style.animationDelay = -Math.random() * 20 + "s";
      p.style.setProperty("--dx", (Math.random() * 160 - 80) + "px");
      p.style.transform = `scale(${.6 + Math.random() * .8})`;
      petals.append(p);
    }
  }

  /* =========================================================
     Gallery + Facebook live feed + map
     ========================================================= */
  const gal = $("#gallery");
  const renderGallery = (items) => gal.replaceChildren(...items.slice(0, 24).map(g => {
    const fig = el("figure", { class: "g", style: "margin:0" });
    const ph = el("div", { class: "ph" });
    ph.innerHTML = '<div><svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m21 17-5-5-8 8"/></svg>Foto: ' + g.caption.replace(/[<>&]/g, "") + "</div>";
    const img = el("img", { src: g.src, alt: g.caption, loading: "lazy" });
    img.addEventListener("error", () => img.remove());
    img.addEventListener("load", () => ph.remove());
    fig.append(ph, img, el("figcaption", { text: g.caption }));
    if (img.complete && img.naturalWidth) ph.remove();
    fig.addEventListener("click", () => {
      if (!fig.contains(img) || !img.complete) return;
      const lb = el("div", { class: "lightbox", role: "dialog", "aria-label": g.caption }, el("img", { src: g.src, alt: g.caption }));
      lb.addEventListener("click", () => lb.remove());
      addEventListener("keydown", function esc(ev) { if (ev.key === "Escape") { lb.remove(); removeEventListener("keydown", esc); } });
      document.body.append(lb);
    });
    return fig;
  }));
  renderGallery(C.gallery || []);
  // Fotos descargadas de Facebook con tools/facebook-fotos.mjs (si existen, reemplazan las de config.js)
  fetch("assets/img/fb/gallery.json").then(r => r.ok ? r.json() : null).then(list => {
    if (Array.isArray(list) && list.length) renderGallery(list);
  }).catch(() => {});

  const fbFrame = $("#fbFrame");
  new IntersectionObserver(([e], obs) => {
    if (!e.isIntersecting) return; obs.disconnect();
    const width = Math.min(500, Math.max(280, Math.floor(fbFrame.clientWidth - 16)));
    const src = "https://www.facebook.com/plugins/page.php?" + new URLSearchParams({
      href: C.facebook, tabs: "timeline,events", width, height: 640,
      small_header: "false", adapt_container_width: "true", hide_cover: "false", show_facepile: "true"
    });
    fbFrame.append(el("iframe", { src, width, height: 640, title: "Publicaciones, fotos y videos de Vida en Cristo en Facebook", loading: "lazy", allow: "encrypted-media; picture-in-picture; web-share", scrolling: "no" }));
  }, { rootMargin: "300px" }).observe(fbFrame);

  const q = encodeURIComponent(C.address || "South Houston, TX");
  $("#mapFrame").src = `https://maps.google.com/maps?q=${q}&z=13&output=embed`;
  $("#mapsLink").href = `https://www.google.com/maps/dir/?api=1&destination=${q}`;

  $("#year").textContent = new Date().getFullYear();

  /* =========================================================
     v2 — preloader, progress, split headings
     ========================================================= */
  const pre = $("#preloader");
  const hidePre = () => pre && pre.classList.add("done");
  if (reduced) hidePre();
  else { const t0 = performance.now(); addEventListener("load", () => setTimeout(hidePre, Math.max(0, 1100 - (performance.now() - t0)))); setTimeout(hidePre, 2600); }

  const bar = $("#scrollBar");
  const onProg = () => { const h = document.documentElement.scrollHeight - innerHeight; bar.style.transform = `scaleX(${h > 0 ? scrollY / h : 0})`; };
  addEventListener("scroll", onProg, { passive: true }); onProg();

  const splitObs = new IntersectionObserver((es) => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); splitObs.unobserve(e.target); } }), { threshold: .3 });
  $$(".section-head h2, .about-text h2, .women-intro h2, .visit h2").forEach(h => {
    let i = 0;
    const wrap = (node) => {
      [...node.childNodes].forEach(n => {
        if (n.nodeType === 3) {
          const frag = document.createDocumentFragment();
          n.textContent.split(/(\s+)/).forEach(part => {
            if (!part) return;
            if (/^\s+$/.test(part)) frag.append(part);
            else { const w = el("span", { class: "w", text: part }); w.style.setProperty("--d", i++); frag.append(w); }
          });
          n.replaceWith(frag);
        } else if (n.nodeType === 1) wrap(n);
      });
    };
    wrap(h); h.classList.remove("reveal"); h.classList.add("split"); splitObs.observe(h);
  });

  /* =========================================================
     Confetti + overlays
     ========================================================= */
  const confetti = (() => {
    const cv = $("#confetti"), ctx = cv.getContext("2d"); let parts = [], raf = 0;
    const colors = ["#f5c46b", "#e89b3c", "#5fae6e", "#3d86c6", "#ff5e8a", "#7c5cff", "#2de2e6", "#fff"];
    const loop = () => {
      ctx.clearRect(0, 0, cv.width, cv.height);
      parts = parts.filter(p => p.y < cv.height + 20 && p.life-- > 0);
      for (const p of parts) {
        p.vy += .25; p.vx *= .99; p.x += p.vx; p.y += p.vy; p.r += p.vr;
        ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.r); ctx.fillStyle = p.c; ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h); ctx.restore();
      }
      raf = parts.length ? requestAnimationFrame(loop) : 0;
    };
    return (n = 160) => {
      if (reduced) return;
      cv.width = innerWidth; cv.height = innerHeight;
      for (let i = 0; i < n; i++) parts.push({ x: innerWidth / 2 + (Math.random() - .5) * 200, y: innerHeight * .45, vx: (Math.random() - .5) * 22, vy: -Math.random() * 18 - 6, r: Math.random() * 6, vr: (Math.random() - .5) * .3, w: 6 + Math.random() * 6, h: 10 + Math.random() * 8, c: colors[i % colors.length], life: 260 });
      if (!raf) raf = requestAnimationFrame(loop);
    };
  })();

  const openOv = (ov) => { ov.hidden = false; document.body.classList.add("locked"); };
  const closeOv = (ov) => { ov.hidden = true; if (!$$(".overlay:not([hidden])").length) document.body.classList.remove("locked"); ov.dispatchEvent(new Event("close")); };
  $$(".overlay [data-close]").forEach(b => b.addEventListener("click", () => closeOv(b.closest(".overlay"))));
  addEventListener("keydown", (e) => { if (e.key === "Escape") { const ov = $$(".overlay:not([hidden])").pop(); if (ov && ov.id !== "silenceOv") closeOv(ov); } });

  /* =========================================================
     Service mode (Modo Culto)
     ========================================================= */
  const MAIN = services.find(s => !s.nth && !s.group) || services[0];
  const ORDER = C.serviceOrder || [];
  const SERVICE_MIN = Math.max(90, (ORDER[ORDER.length - 1]?.at || 90) + 20);
  const serviceState = () => {
    const now = nowInTz(); if (!MAIN) return null;
    const [h, m] = MAIN.time.split(":").map(Number);
    const today = new Date(now); today.setHours(h, m, 0, 0);
    if (matches(MAIN, today) && now >= today && now - today < SERVICE_MIN * 6e4) return { live: true, start: today, elapsed: (now - today) / 6e4, now };
    return { live: false, start: occurrences(MAIN, now)[0], now };
  };
  const hhmm = (d) => d.toLocaleTimeString("es-US", { hour: "numeric", minute: "2-digit" });

  const orderList = $("#serviceOrder");
  const renderOrder = (st) => {
    const start = st.start;
    const cur = st.live ? ORDER.reduce((k, it, i) => st.elapsed >= it.at ? i : k, 0) : -1;
    orderList.replaceChildren(el("span", { class: "bar" }), ...ORDER.map((it, i) => {
      const t = new Date(start.getTime() + it.at * 6e4);
      return el("li", { class: i < cur ? "done" : i === cur ? "now" : "" }, el("span", { class: "ico", text: it.icon }), el("b", { text: it.title }), el("small", { text: hhmm(t) }));
    }));
    requestAnimationFrame(() => {
      const nowLi = $("li.now", orderList), b = $(".bar", orderList);
      if (nowLi) b.style.height = (nowLi.offsetTop + nowLi.offsetHeight / 2 - 10) + "px";
    });
  };

  const silenceKey = (st) => "silenced_" + st.start.toDateString();
  const showSilence = () => { openOv($("#silenceOv")); try { navigator.vibrate?.([250, 120, 250, 120, 400]); } catch {} };
  $("#silenceDone").addEventListener("click", () => {
    const st = serviceState(); if (st?.live) store.set(silenceKey(st), true);
    closeOv($("#silenceOv")); confetti(80); toast("🙏 ¡Gracias! Que disfrutes la presencia de Dios.");
  });
  $("#silenceTest").addEventListener("click", showSilence);
  const silenceBtn = $("#silenceEnable");
  const syncSilenceBtn = () => { if (store.get("silenceOn", false)) { silenceBtn.textContent = "✅ Aviso activado"; } };
  syncSilenceBtn();
  silenceBtn.addEventListener("click", async () => {
    store.set("silenceOn", true); syncSilenceBtn();
    try { if ("Notification" in window && Notification.permission === "default") await Notification.requestPermission(); } catch {}
    toast("🔔 Te avisaremos al comenzar el culto si tienes esta página abierta. También puedes agregar el culto a tu calendario.");
  });

  let notified = false;
  const tickService = () => {
    const st = serviceState(); if (!st || !st.start) return;
    const box = $("#cultoStatus");
    box.classList.toggle("live", st.live);
    if (st.live) {
      const cur = ORDER.reduce((k, it) => st.elapsed >= it.at ? it : k, ORDER[0]);
      box.replaceChildren(el("span", { class: "live-dot" }), el("span", { text: `El culto está en vivo · Ahora: ${cur ? cur.icon + " " + cur.title : ""}` }));
      if (st.elapsed < 20 && !store.get(silenceKey(st), false) && $("#silenceOv").hidden) {
        showSilence();
        if (!notified && store.get("silenceOn", false) && "Notification" in window && Notification.permission === "granted") {
          notified = true; try { new Notification("Vida en Cristo", { body: "El culto está comenzando. Silencia tu teléfono 🔕", icon: "assets/img/mark.svg" }); } catch {}
        }
      }
    } else {
      box.replaceChildren(el("span", { class: "live-dot" }), el("span", { text: `Próximo culto: ${st.start.toLocaleDateString("es-US", { weekday: "long", day: "numeric", month: "long" })} · ${hhmm(st.start)}` }));
    }
    renderOrder(st);
  };
  tickService(); setInterval(tickService, 20000);

  /* sermon outline */
  const SER = C.sermon || { title: "", passage: "", points: [] };
  const today8 = new Date().toISOString().slice(0, 10);
  $("#sermonTag").textContent = SER.example ? "Bosquejo de ejemplo" : "Sermón de hoy";
  $("#sermonTitle").textContent = SER.title;
  $("#sermonPassage").textContent = SER.passage;
  const revealed = new Set(store.get("blanks_" + today8, []));
  const withBlanks = (txt, key) => {
    const frag = document.createDocumentFragment();
    txt.split(/(\[[^\]]+\])/).forEach((part, j) => {
      const mm = part.match(/^\[(.+)\]$/);
      if (!mm) { frag.append(part); return; }
      const id = key + ":" + j;
      const b = el("button", { class: "blank" + (revealed.has(id) ? " on" : ""), text: mm[1], "aria-label": revealed.has(id) ? mm[1] : "Revelar palabra" });
      b.addEventListener("click", (e) => {
        if (b.classList.contains("on")) return;
        b.classList.add("on"); b.setAttribute("aria-label", mm[1]); revealed.add(id); store.set("blanks_" + today8, [...revealed]);
        sparks(e.clientX, e.clientY);
        if ($$("#sermonPoints .blank").every(x => x.classList.contains("on"))) { confetti(90); toast("📖 ¡Completaste el bosquejo!"); }
      });
      frag.append(b);
    });
    return frag;
  };
  $("#sermonPoints").replaceChildren(...SER.points.map((pt, i) => el("li", {}, el("span", {}, withBlanks(pt.title, "p" + i)))));

  /* notes */
  const notesKey = "notes_" + today8, notes = $("#notesArea");
  notes.value = store.get(notesKey, "");
  let nt; notes.addEventListener("input", () => { clearTimeout(nt); nt = setTimeout(() => { store.set(notesKey, notes.value); $("#notesSaved").textContent = "✓ Guardado en tu teléfono"; }, 400); });
  $("#notesShare").addEventListener("click", async () => {
    const text = `${SER.title} (${SER.passage})\n\n${notes.value}\n\n— Iglesia Bautista Vida en Cristo`;
    try { if (navigator.share) await navigator.share({ text }); else { await navigator.clipboard.writeText(text); toast("📋 Notas copiadas"); } } catch {}
  });

  /* preaching mode */
  const smOv = $("#sermonOv"), stage = $("#smStage");
  const slides = [
    { kind: "intro" },
    ...SER.points.map((p, i) => ({ kind: "point", i, ...p })),
    { kind: "end" }
  ];
  let si = 0, smT0 = 0, smTimer = 0, wake = null, smAnim = 0;
  const fmtClock = (ms) => { const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s2 = t % 60; return (h ? h + ":" : "") + String(m).padStart(2, "0") + ":" + String(s2).padStart(2, "0"); };
  const renderSlide = () => {
    const sl = slides[si];
    let node;
    if (sl.kind === "intro") node = el("div", { class: "sm-slide" }, el("p", { class: "eyebrow", text: "Predicación" }), el("h2", { text: SER.title }), el("p", { class: "sm-verse", text: SER.passage }));
    else if (sl.kind === "end") node = el("div", { class: "sm-slide" }, el("div", { class: "sm-num", text: "✦" }), el("h2", { text: "Amén" }), el("p", { text: "Lleva esta Palabra contigo esta semana. Dios te bendiga." }));
    else {
      const h = el("h2");
      sl.title.split(/(\[[^\]]+\])/).forEach(part => { const mm = part.match(/^\[(.+)\]$/); h.append(mm ? el("span", { class: "reveal-word", text: mm[1] }) : part); });
      node = el("div", { class: "sm-slide" }, el("div", { class: "sm-num", text: String(sl.i + 1) }), h, el("p", { text: sl.text || "" }), sl.verse ? el("div", { class: "sm-verse", text: sl.verse }) : null);
    }
    stage.replaceChildren(node);
    $("#smDots").replaceChildren(...slides.map((_, k) => el("button", { class: k === si ? "on" : "", "aria-label": `Ir a ${k + 1}`, onclick: () => { si = k; renderSlide(); } })));
    $("#smPrev").disabled = si === 0; $("#smNext").textContent = si === slides.length - 1 ? "Terminar" : "Siguiente →";
  };
  const smParticles = () => {
    const cv = $("#smCanvas"), ctx = cv.getContext("2d");
    const dpr = Math.min(devicePixelRatio || 1, 2); cv.width = innerWidth * dpr; cv.height = innerHeight * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const ps = Array.from({ length: 70 }, () => ({ x: Math.random() * innerWidth, y: Math.random() * innerHeight, r: Math.random() * 1.6 + .3, v: Math.random() * .3 + .05, t: Math.random() * 6 }));
    const frame = () => {
      if (smOv.hidden) return;
      ctx.clearRect(0, 0, innerWidth, innerHeight);
      for (const p of ps) { p.y -= p.v; p.t += .02; if (p.y < -5) { p.y = innerHeight + 5; p.x = Math.random() * innerWidth; } ctx.globalAlpha = .4 + Math.sin(p.t) * .3; ctx.fillStyle = "#f5c46b"; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, 7); ctx.fill(); }
      smAnim = requestAnimationFrame(frame);
    };
    if (!reduced) frame();
  };
  const openSermon = async () => {
    si = 0; renderSlide(); openOv(smOv);
    $("#smTitle").textContent = SER.title; $("#smPassage").textContent = SER.passage;
    smT0 = Date.now(); $("#smClock").textContent = "00:00";
    smTimer = setInterval(() => $("#smClock").textContent = fmtClock(Date.now() - smT0), 1000);
    smParticles();
    try { await smOv.requestFullscreen?.(); } catch {}
    try { wake = await navigator.wakeLock?.request("screen"); } catch {}
  };
  const closeSermon = () => {
    clearInterval(smTimer); cancelAnimationFrame(smAnim); try { wake?.release(); } catch {} wake = null;
    if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {});
    closeOv(smOv);
  };
  $("#sermonOpen").addEventListener("click", openSermon);
  $("#smClose").addEventListener("click", closeSermon);
  $("#smPrev").addEventListener("click", () => { if (si > 0) { si--; renderSlide(); } });
  $("#smNext").addEventListener("click", () => { if (si < slides.length - 1) { si++; renderSlide(); if (si === slides.length - 1) confetti(60); } else closeSermon(); });
  addEventListener("keydown", (e) => {
    if (smOv.hidden) return;
    if (e.key === "ArrowRight" || e.key === " " || e.key === "PageDown") { e.preventDefault(); $("#smNext").click(); }
    if (e.key === "ArrowLeft" || e.key === "PageUp") { e.preventDefault(); $("#smPrev").click(); }
    if (e.key === "Escape") closeSermon();
  });
  document.addEventListener("fullscreenchange", () => { if (!document.fullscreenElement && !smOv.hidden) { /* stay open in window */ } });

  /* =========================================================
     Youth live dynamics: team trivia + wheel
     ========================================================= */
  const TQ_SEC = 20, CIRC = 302;
  const tv = { names: store.get("teams", ["Fuego", "Luz"]), score: [0, 0], qs: [], i: 0, timer: 0, left: 0 };
  const trivia = $("#trivia");
  const teamsBar = (award) => el("div", { class: "teams" }, ...[0, 1].map(k => {
    const box = el("div", { class: "team " + (k ? "light" : "fire") },
      el("input", { value: tv.names[k], "aria-label": "Nombre del equipo", maxlength: "16", oninput: (e) => { tv.names[k] = e.target.value || (k ? "Luz" : "Fuego"); store.set("teams", tv.names); } }),
      el("b", { text: String(tv.score[k]) }));
    if (award) box.append(el("button", { class: "btn btn-sm add " + (k ? "btn-light" : "btn-fire"), text: `+100 ${k ? "💧" : "🔥"}`, onclick: (e) => { tv.score[k] += 100; sparks(e.clientX, e.clientY); nextQ(); } }));
    return box;
  }));
  const triviaSetup = () => {
    tv.score = [0, 0]; tv.i = 0; tv.qs = shuffle(QUIZ).slice(0, 10);
    trivia.replaceChildren(el("p", { class: "eyebrow eyebrow-neon", text: "Jóvenes Vida en Cristo" }), el("h2", { text: "Trivia bíblica por equipos" }), teamsBar(false),
      el("p", { class: "small", style: "color:#a9a3c9;margin-bottom:1.4rem", text: "10 preguntas · 20 segundos cada una · El líder marca qué equipo acertó primero." }),
      el("button", { class: "btn btn-neon", text: "¡Comenzar!", onclick: showQ }));
  };
  const showQ = () => {
    const [q, opts] = tv.qs[tv.i]; tv.left = TQ_SEC;
    const ring = el("div", { class: "ring-timer" });
    ring.innerHTML = `<svg viewBox="0 0 110 110"><defs><linearGradient id="rtGrad"><stop offset="0" stop-color="#7c5cff"/><stop offset="1" stop-color="#2de2e6"/></linearGradient></defs><circle class="bg" cx="55" cy="55" r="48"/><circle class="fg" cx="55" cy="55" r="48" style="stroke-dashoffset:0"/></svg><span>${TQ_SEC}</span>`;
    trivia.replaceChildren(teamsBar(false), el("p", { class: "small", style: "color:#a9a3c9", text: `Pregunta ${tv.i + 1} de ${tv.qs.length}` }), ring,
      el("h2", { text: q }),
      el("div", { class: "t-opts" }, ...opts.map((o, k) => el("div", { class: "t-opt" }, el("i", { text: "ABCD"[k] }), el("span", { text: o })))),
      el("div", { class: "t-actions" }, el("button", { class: "btn btn-gold", text: "Revelar respuesta", onclick: reveal })));
    clearInterval(tv.timer);
    tv.timer = setInterval(() => {
      tv.left--; $("span", ring).textContent = Math.max(0, tv.left);
      $(".fg", ring).style.strokeDashoffset = CIRC * (1 - tv.left / TQ_SEC);
      ring.classList.toggle("low", tv.left <= 5);
      if (tv.left <= 0) reveal();
    }, 1000);
  };
  const reveal = () => {
    clearInterval(tv.timer);
    const ans = tv.qs[tv.i][2];
    $$(".t-opt", trivia).forEach((o, k) => o.classList.add(k === ans ? "right" : "dim"));
    $(".t-actions", trivia).replaceChildren(el("p", { style: "width:100%;margin:0 0 .4rem;color:#a9a3c9", text: "¿Qué equipo acertó?" }), ...$$(".team .add", teamsBar(true)), el("button", { class: "btn btn-ghost", text: "Nadie", onclick: nextQ }));
  };
  const nextQ = () => {
    tv.i++;
    if (tv.i < tv.qs.length) { showQ(); return; }
    const w = tv.score[0] === tv.score[1] ? null : tv.score[0] > tv.score[1] ? 0 : 1;
    trivia.replaceChildren(el("p", { class: "eyebrow eyebrow-neon", text: "Resultado final" }),
      el("div", { class: "winner", text: w === null ? "¡Empate! 🤝" : `¡Gana ${tv.names[w]}! ${w ? "💧" : "🔥"}` }), teamsBar(false),
      el("button", { class: "btn btn-neon", text: "Jugar otra vez", onclick: triviaSetup }));
    confetti(220);
  };
  $("#openTrivia").addEventListener("click", () => { triviaSetup(); openOv($("#triviaOv")); $("#triviaOv").requestFullscreen?.().catch(() => {}); });
  $("#triviaOv").addEventListener("close", () => { clearInterval(tv.timer); if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {}); });

  const DEFAULT_WHEEL = ["Di tu versículo favorito", "Ora por la persona a tu derecha", "Canta el coro de una alabanza", "Cuenta un testimonio", "Menciona 3 libros del A.T.", "Abraza a alguien 🤗", "Recita Juan 3:16", "Di algo bueno de alguien del grupo"];
  const wItems = $("#wheelItems"), wCv = $("#wheelCanvas"), wCtx = wCv.getContext("2d");
  wItems.value = store.get("wheel", DEFAULT_WHEEL).join("\n");
  const WCOL = ["#7c5cff", "#2de2e6", "#ff5e8a", "#f5a623", "#3d86c6", "#5fae6e", "#e89b3c", "#a855f7"];
  let wAngle = 0, spinning = false;
  const items = () => wItems.value.split("\n").map(x => x.trim()).filter(Boolean).slice(0, 24);
  const drawWheel = () => {
    const it = items(), n = Math.max(it.length, 1), R = 270, c = 280; wCtx.clearRect(0, 0, 560, 560);
    for (let k = 0; k < n; k++) {
      const a0 = wAngle + k * 2 * Math.PI / n, a1 = a0 + 2 * Math.PI / n;
      wCtx.beginPath(); wCtx.moveTo(c, c); wCtx.arc(c, c, R, a0, a1); wCtx.closePath();
      wCtx.fillStyle = WCOL[k % WCOL.length]; wCtx.fill(); wCtx.strokeStyle = "rgba(255,255,255,.35)"; wCtx.lineWidth = 2; wCtx.stroke();
      wCtx.save(); wCtx.translate(c, c); wCtx.rotate(a0 + Math.PI / n); wCtx.textAlign = "right"; wCtx.fillStyle = "#fff";
      const label = (it[k] || "Agrega opciones").slice(0, 34), maxW = R - 18 - 62;
      let fs = n > 12 ? 15 : 19; do { wCtx.font = `700 ${fs}px Inter, sans-serif`; } while (wCtx.measureText(label).width > maxW && --fs > 9);
      wCtx.fillText(label, R - 18, fs / 3); wCtx.restore();
    }
    wCtx.beginPath(); wCtx.arc(c, c, R, 0, 7); wCtx.strokeStyle = "#ffd56b"; wCtx.lineWidth = 8; wCtx.stroke();
  };
  wItems.addEventListener("input", () => { store.set("wheel", items()); drawWheel(); });
  $("#wheelSpin").addEventListener("click", () => {
    const it = items(); if (spinning || it.length < 2) return;
    spinning = true; $("#wheelSpin").disabled = true; const res = $("#wheelResult"); res.classList.remove("on"); res.textContent = "…";
    const start = wAngle, total = (6 + Math.random() * 4) * 2 * Math.PI, dur = reduced ? 10 : 5200, t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / dur); wAngle = start + total * (1 - Math.pow(1 - k, 4)); drawWheel();
      if (k < 1) { requestAnimationFrame(step); return; }
      const n = it.length, pointer = -Math.PI / 2;
      const idx = Math.floor((((pointer - wAngle) % (2 * Math.PI) + 4 * Math.PI) % (2 * Math.PI)) / (2 * Math.PI / n));
      res.textContent = "🎉 " + it[idx]; res.classList.add("on"); confetti(140);
      spinning = false; $("#wheelSpin").disabled = false;
    };
    requestAnimationFrame(step);
  });
  $("#openWheel").addEventListener("click", () => { openOv($("#wheelOv")); drawWheel(); });
})();
