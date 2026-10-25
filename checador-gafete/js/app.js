/*
 * Checador con gafete obligatorio.
 *
 * Flujo de checada:
 *   1. El empleado escanea el QR de su gafete (cámara o lector USB). Sin gafete no avanza.
 *   2. Ingresa su PIN personal (evita que alguien use el gafete de otro).
 *   3. Se toma una foto con el gafete puesto en el uniforme (opcional en Ajustes).
 *   4. Elige Entrada / Descanso / Salida.
 * Si no trae gafete, solo un gerente puede autorizar la checada con su PIN y queda como incidente.
 *
 * Todo se guarda en localStorage del dispositivo (pensado para una tablet fija como kiosco).
 */
(() => {
  'use strict';

  // ---------------------------------------------------------------- datos
  const KEY = 'checador-gafete-v1';
  const IDLE_MS = 30000;
  const PUNCH_LABELS = { in: 'Entrada', break_start: 'Inicio descanso', break_end: 'Fin descanso', out: 'Salida' };

  const defaults = () => ({
    settings: { storeName: 'Mi tienda', requirePhoto: true, managerName: 'Gerente', managerPinHash: '', photoDays: 30 },
    employees: [],
    punches: [],
  });

  let db = load();

  function load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const data = JSON.parse(raw);
        const base = defaults();
        return { ...base, ...data, settings: { ...base.settings, ...data.settings } };
      }
    } catch (e) { console.error(e); }
    return defaults();
  }

  function save() {
    pruneOldPhotos();
    try {
      localStorage.setItem(KEY, JSON.stringify(db));
    } catch (e) {
      // Memoria llena: quitamos las fotos más viejas y reintentamos.
      const withPhoto = db.punches.filter(p => p.photo);
      withPhoto.slice(0, Math.ceil(withPhoto.length / 2)).forEach(p => { p.photo = ''; });
      localStorage.setItem(KEY, JSON.stringify(db));
    }
  }

  function pruneOldPhotos() {
    const limit = Date.now() - db.settings.photoDays * 86400000;
    db.punches.forEach(p => { if (p.photo && p.ts < limit) p.photo = ''; });
  }

  async function hash(text) {
    const data = new TextEncoder().encode('checador:' + text);
    if (window.crypto && crypto.subtle) {
      const buf = await crypto.subtle.digest('SHA-256', data);
      return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
    }
    // Respaldo si la página no se sirve por https/localhost (la cámara tampoco funcionará).
    let h = 2166136261;
    for (const b of data) { h ^= b; h = Math.imul(h, 16777619); }
    return 'fnv' + (h >>> 0).toString(16);
  }

  function newBadgeCode() {
    const bytes = new Uint8Array(8);
    crypto.getRandomValues(bytes);
    return 'GAF1-' + [...bytes].map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  }

  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const $ = sel => document.querySelector(sel);
  const $$ = sel => [...document.querySelectorAll(sel)];
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const initials = name => name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('');
  const fmtTime = ts => new Date(ts).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' });
  const fmtDateTime = ts => new Date(ts).toLocaleString('es', { dateStyle: 'short', timeStyle: 'short' });
  const empById = id => db.employees.find(e => e.id === id);
  const lastPunch = empId => [...db.punches].reverse().find(p => p.empId === empId);

  function allowedPunches(empId) {
    const last = lastPunch(empId);
    if (!last || last.type === 'out') return ['in'];
    if (last.type === 'break_start') return ['break_end', 'out'];
    return ['break_start', 'out'];
  }

  // ---------------------------------------------------------------- cámara
  let stream = null;
  let scanLoop = null;

  async function startCamera(video) {
    stopCamera();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: 640, height: 480 }, audio: false });
      video.srcObject = stream;
      await video.play();
      return true;
    } catch (e) {
      console.warn('Cámara no disponible', e);
      return false;
    }
  }

  function stopCamera() {
    if (scanLoop) { cancelAnimationFrame(scanLoop); scanLoop = null; }
    if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; }
  }

  async function startScanning() {
    const video = $('#scanVideo');
    const ok = await startCamera(video);
    if (!ok) {
      $('#scanError').textContent = 'No hay cámara disponible. Usa el lector USB o escribe el código del gafete.';
      return;
    }
    const detector = 'BarcodeDetector' in window ? new BarcodeDetector({ formats: ['qr_code'] }) : null;
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    let busy = false;

    const tick = async () => {
      if (!stream) return;
      if (!busy && video.readyState >= 2) {
        busy = true;
        try {
          let value = null;
          if (detector) {
            const codes = await detector.detect(video);
            value = codes[0]?.rawValue;
          } else if (window.jsQR) {
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            ctx.drawImage(video, 0, 0);
            const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
            value = jsQR(img.data, img.width, img.height)?.data;
          }
          if (value) { handleBadge(value); busy = false; return; }
        } catch (e) { console.warn(e); }
        busy = false;
      }
      scanLoop = requestAnimationFrame(tick);
    };
    scanLoop = requestAnimationFrame(tick);
  }

  // ---------------------------------------------------------------- kiosco
  const session = { emp: null, method: 'badge', overrideReason: '', photo: '', pin: '' };
  let idleTimer = null;

  function showStep(name) {
    $$('#view-kiosk .step').forEach(s => s.classList.toggle('active', s.id === 'step-' + name));
    clearTimeout(idleTimer);
    if (name !== 'scan') idleTimer = setTimeout(resetKiosk, IDLE_MS);
  }

  function resetKiosk() {
    stopCamera();
    Object.assign(session, { emp: null, method: 'badge', overrideReason: '', photo: '', pin: '' });
    $('#scanError').textContent = '';
    $('#scannerInput').value = '';
    showStep('scan');
    if ($('#view-kiosk').classList.contains('active')) {
      startScanning();
      $('#scannerInput').focus();
    }
  }

  function handleBadge(code) {
    code = code.trim().toUpperCase();
    const emp = db.employees.find(e => e.badgeCode === code);
    if (!emp) {
      $('#scanError').textContent = 'Gafete no reconocido. Si te dieron uno nuevo, pide al gerente que lo registre.';
      return;
    }
    if (!emp.active) {
      $('#scanError').textContent = 'Este gafete está desactivado. Habla con tu gerente.';
      return;
    }
    stopCamera();
    session.emp = emp;
    session.method = 'badge';
    session.pin = '';
    $('#whoName').textContent = emp.name;
    $('#whoRole').textContent = emp.role || '';
    $('#whoInitials').textContent = initials(emp.name);
    $('#pinError').textContent = '';
    renderPinDots();
    showStep('pin');
  }

  function renderPinDots() {
    $('#pinDots').innerHTML = Array.from({ length: Math.max(4, session.pin.length) },
      (_, i) => `<span class="${i < session.pin.length ? 'filled' : ''}"></span>`).join('');
  }

  function buildKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '✓'];
    $('#keypad').innerHTML = keys.map(k => `<button type="button" data-key="${k}">${k}</button>`).join('');
    $('#keypad').addEventListener('click', e => {
      const k = e.target.dataset.key;
      if (!k) return;
      showStep('pin'); // reinicia el temporizador de inactividad
      if (k === '⌫') session.pin = session.pin.slice(0, -1);
      else if (k === '✓') return checkPin();
      else if (session.pin.length < 6) session.pin += k;
      renderPinDots();
    });
  }

  async function checkPin() {
    if ((await hash(session.pin)) !== session.emp.pinHash) {
      session.pin = '';
      renderPinDots();
      $('#pinError').textContent = 'PIN incorrecto.';
      return;
    }
    goToPhotoOrConfirm();
  }

  async function goToPhotoOrConfirm() {
    if (db.settings.requirePhoto) {
      showStep('photo');
      $('#countdown').textContent = '';
      const ok = await startCamera($('#photoVideo'));
      if (!ok) {
        session.photo = '';
        return showConfirm();
      }
    } else {
      showConfirm();
    }
  }

  function takePhoto() {
    const video = $('#photoVideo');
    const btn = $('#takePhotoBtn');
    btn.disabled = true;
    let n = 3;
    $('#countdown').textContent = n;
    const timer = setInterval(() => {
      n -= 1;
      if (n > 0) { $('#countdown').textContent = n; return; }
      clearInterval(timer);
      $('#countdown').textContent = '';
      const canvas = document.createElement('canvas');
      const w = 320;
      canvas.width = w;
      canvas.height = Math.round(w * (video.videoHeight || 480) / (video.videoWidth || 640));
      canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      session.photo = canvas.toDataURL('image/jpeg', 0.6);
      btn.disabled = false;
      stopCamera();
      showConfirm();
    }, 1000);
  }

  function showConfirm() {
    const allowed = allowedPunches(session.emp.id);
    $('#confirmTitle').textContent = `Hola, ${session.emp.name.split(' ')[0]}`;
    $('#confirmPhoto').src = session.photo || '';
    $$('[data-punch]').forEach(b => { b.disabled = !allowed.includes(b.dataset.punch); });
    showStep('confirm');
  }

  function recordPunch(type) {
    const punch = {
      id: uid(),
      empId: session.emp.id,
      type,
      ts: Date.now(),
      method: session.method,
      photo: session.photo,
    };
    if (session.method === 'override') {
      punch.overrideBy = db.settings.managerName;
      punch.overrideReason = session.overrideReason;
    }
    db.punches.push(punch);
    save();

    const icon = $('#doneIcon');
    icon.classList.toggle('warn', session.method === 'override');
    icon.textContent = session.method === 'override' ? '!' : '✔';
    $('#doneTitle').textContent = `${PUNCH_LABELS[type]} registrada · ${fmtTime(punch.ts)}`;
    $('#doneMsg').textContent = session.method === 'override'
      ? 'Checada sin gafete: quedó registrada como incidente. Trae tu gafete en el próximo turno.'
      : `${session.emp.name}, gracias por traer tu gafete.`;
    showStep('done');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(resetKiosk, 4000);
  }

  function openOverride() {
    stopCamera();
    const active = db.employees.filter(e => e.active);
    $('#overrideEmp').innerHTML = active.map(e => `<option value="${e.id}">${esc(e.name)}</option>`).join('');
    $('#overridePin').value = '';
    $('#overrideError').textContent = active.length ? '' : 'No hay empleados registrados.';
    showStep('override');
  }

  async function authorizeOverride() {
    const emp = empById($('#overrideEmp').value);
    if (!emp) return;
    if (!db.settings.managerPinHash || (await hash($('#overridePin').value)) !== db.settings.managerPinHash) {
      $('#overrideError').textContent = 'PIN de gerente incorrecto.';
      return;
    }
    session.emp = emp;
    session.method = 'override';
    session.overrideReason = $('#overrideReason').value;
    goToPhotoOrConfirm();
  }

  // ---------------------------------------------------------------- gerente
  let adminUnlocked = false;

  function showView(name) {
    $$('.view').forEach(v => v.classList.toggle('active', v.id === 'view-' + name));
    $$('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.view === name));
    if (name === 'kiosk') {
      resetKiosk();
    } else {
      stopCamera();
      clearTimeout(idleTimer);
      renderAdmin();
    }
  }

  function renderAdmin() {
    const firstRun = !db.settings.managerPinHash;
    $('#adminLock').hidden = adminUnlocked;
    $('#adminPanel').hidden = !adminUnlocked;
    $('#adminPin2').hidden = !firstRun;
    $('#adminLockTitle').textContent = firstRun ? 'Crea el PIN de gerente' : 'Acceso de gerente';
    $('#adminLockHint').textContent = firstRun ? 'Primera vez: elige un PIN de 4 a 8 dígitos. Lo necesitarás para administrar y autorizar checadas sin gafete.' : '';
    $('#adminLoginBtn').textContent = firstRun ? 'Crear PIN' : 'Entrar';
    if (adminUnlocked) {
      renderTeam();
      renderLog();
      renderIncidents();
      fillSettings();
    }
  }

  async function adminLogin() {
    const pin = $('#adminPin').value;
    const err = $('#adminError');
    if (!db.settings.managerPinHash) {
      if (!/^\d{4,8}$/.test(pin)) return (err.textContent = 'El PIN debe tener de 4 a 8 dígitos.');
      if (pin !== $('#adminPin2').value) return (err.textContent = 'Los PIN no coinciden.');
      db.settings.managerPinHash = await hash(pin);
      save();
    } else if ((await hash(pin)) !== db.settings.managerPinHash) {
      return (err.textContent = 'PIN incorrecto.');
    }
    err.textContent = '';
    $('#adminPin').value = '';
    $('#adminPin2').value = '';
    adminUnlocked = true;
    renderAdmin();
  }

  function incidentCount(empId) {
    return db.punches.filter(p => p.empId === empId && p.method === 'override').length;
  }

  function renderTeam() {
    $('#empTable').innerHTML = db.employees.map(e => `
      <tr>
        <td>${esc(e.name)}</td>
        <td>${esc(e.role)}</td>
        <td><span class="badge ${e.active ? 'green' : ''}">${e.active ? 'Activo' : 'Inactivo'}</span></td>
        <td><span class="badge ${incidentCount(e.id) ? 'red' : ''}">${incidentCount(e.id)}</span></td>
        <td><div class="actions">
          <button data-act="print" data-id="${e.id}">Imprimir QR</button>
          <button data-act="regen" data-id="${e.id}">Gafete nuevo</button>
          <button data-act="pin" data-id="${e.id}">Cambiar PIN</button>
          <button data-act="toggle" data-id="${e.id}">${e.active ? 'Desactivar' : 'Activar'}</button>
        </div></td>
      </tr>`).join('') || '<tr><td colspan="5" class="muted">Aún no hay empleados.</td></tr>';
  }

  async function addEmployee(form) {
    const data = Object.fromEntries(new FormData(form));
    db.employees.push({
      id: uid(),
      name: data.name.trim(),
      role: data.role.trim(),
      pinHash: await hash(data.pin),
      badgeCode: newBadgeCode(),
      active: true,
    });
    save();
    form.reset();
    renderTeam();
  }

  async function employeeAction(act, id) {
    const emp = empById(id);
    if (!emp) return;
    if (act === 'print') return printBadge(emp);
    if (act === 'regen') {
      if (!confirm(`¿Generar gafete nuevo para ${emp.name}? El código anterior dejará de funcionar.`)) return;
      emp.badgeCode = newBadgeCode();
      save();
      return printBadge(emp);
    }
    if (act === 'pin') {
      const pin = prompt(`Nuevo PIN para ${emp.name} (4-6 dígitos):`);
      if (pin === null) return;
      if (!/^\d{4,6}$/.test(pin)) return alert('El PIN debe tener de 4 a 6 dígitos.');
      emp.pinHash = await hash(pin);
    }
    if (act === 'toggle') emp.active = !emp.active;
    save();
    renderTeam();
  }

  function printBadge(emp) {
    if (!window.QRCode) return alert('No se pudo cargar el generador de QR. Revisa la conexión a internet.');
    const sheet = $('#printSheet');
    sheet.innerHTML = `
      <div class="sticker">
        <div class="qr" id="qrTarget"></div>
        <div class="name">${esc(emp.name)}</div>
        <div class="code">${esc(emp.badgeCode)}</div>
      </div>`;
    new QRCode($('#qrTarget'), { text: emp.badgeCode, width: 256, height: 256, correctLevel: QRCode.CorrectLevel.M });
    // Espera a que se dibuje el QR antes de abrir el diálogo de impresión.
    setTimeout(() => window.print(), 300);
  }

  function punchesForDate(dateStr) {
    const start = new Date(dateStr + 'T00:00:00').getTime();
    const end = start + 86400000;
    return db.punches.filter(p => p.ts >= start && p.ts < end);
  }

  function renderLog() {
    const input = $('#logDate');
    if (!input.value) input.value = new Date().toLocaleDateString('en-CA');
    const rows = punchesForDate(input.value).reverse();
    $('#logTable').innerHTML = rows.map(p => `
      <tr>
        <td>${fmtTime(p.ts)}</td>
        <td>${esc(empById(p.empId)?.name || '—')}</td>
        <td>${PUNCH_LABELS[p.type]}</td>
        <td><span class="badge ${p.method === 'override' ? 'red' : 'green'}">${p.method === 'override' ? 'Sin gafete' : 'Gafete'}</span></td>
        <td>${p.photo ? `<img src="${p.photo}" alt="foto" data-full>` : '—'}</td>
      </tr>`).join('') || '<tr><td colspan="5" class="muted">Sin registros este día.</td></tr>';
  }

  function renderIncidents() {
    const rows = db.punches.filter(p => p.method === 'override').reverse();
    $('#incTable').innerHTML = rows.map(p => `
      <tr>
        <td>${fmtDateTime(p.ts)}</td>
        <td>${esc(empById(p.empId)?.name || '—')}</td>
        <td>${esc(p.overrideReason)}</td>
        <td>${esc(p.overrideBy)}</td>
      </tr>`).join('') || '<tr><td colspan="4" class="muted">Ningún incidente. ¡Todos traen su gafete!</td></tr>';
  }

  function exportCsv() {
    const header = ['fecha', 'hora', 'empleado', 'tipo', 'metodo', 'motivo_sin_gafete', 'autorizo'];
    const rows = punchesForDate($('#logDate').value).map(p => {
      const d = new Date(p.ts);
      return [
        d.toLocaleDateString('en-CA'),
        d.toLocaleTimeString('es', { hour12: false }),
        empById(p.empId)?.name || '',
        PUNCH_LABELS[p.type],
        p.method === 'override' ? 'sin gafete' : 'gafete',
        p.overrideReason || '',
        p.overrideBy || '',
      ];
    });
    const csv = [header, ...rows].map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
    a.download = `checadas-${$('#logDate').value}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  function fillSettings() {
    const f = $('#settingsForm');
    f.storeName.value = db.settings.storeName;
    f.requirePhoto.checked = db.settings.requirePhoto;
    f.managerName.value = db.settings.managerName;
    f.photoDays.value = db.settings.photoDays;
    f.managerPin.value = '';
    $('#settingsMsg').textContent = '';
  }

  async function saveSettings(f) {
    db.settings.storeName = f.storeName.value.trim() || 'Mi tienda';
    db.settings.requirePhoto = f.requirePhoto.checked;
    db.settings.managerName = f.managerName.value.trim() || 'Gerente';
    db.settings.photoDays = Math.min(90, Math.max(1, Number(f.photoDays.value) || 30));
    if (f.managerPin.value) db.settings.managerPinHash = await hash(f.managerPin.value);
    save();
    applyStoreName();
    fillSettings();
    $('#settingsMsg').textContent = 'Guardado.';
  }

  function applyStoreName() {
    $('#storeName').textContent = db.settings.storeName;
  }

  // ---------------------------------------------------------------- eventos
  function bind() {
    $$('.nav-btn').forEach(b => b.addEventListener('click', () => showView(b.dataset.view)));
    $$('[data-cancel]').forEach(b => b.addEventListener('click', resetKiosk));

    $('#scannerForm').addEventListener('submit', e => {
      e.preventDefault();
      const v = $('#scannerInput').value;
      $('#scannerInput').value = '';
      if (v.trim()) handleBadge(v);
    });
    $('#noBadgeBtn').addEventListener('click', openOverride);
    $('#overrideBtn').addEventListener('click', authorizeOverride);
    $('#takePhotoBtn').addEventListener('click', takePhoto);
    $$('[data-punch]').forEach(b => b.addEventListener('click', () => recordPunch(b.dataset.punch)));

    // Teclado físico también sirve para el PIN.
    document.addEventListener('keydown', e => {
      if (!$('#step-pin').classList.contains('active')) return;
      if (/^\d$/.test(e.key)) $(`#keypad [data-key="${e.key}"]`).click();
      else if (e.key === 'Backspace') $('#keypad [data-key="⌫"]').click();
      else if (e.key === 'Enter') $('#keypad [data-key="✓"]').click();
    });

    $('#adminLoginBtn').addEventListener('click', adminLogin);
    $('#adminPin').addEventListener('keydown', e => { if (e.key === 'Enter') adminLogin(); });
    $('#lockBtn').addEventListener('click', () => { adminUnlocked = false; showView('kiosk'); });

    $$('.tab[data-tab]').forEach(t => t.addEventListener('click', () => {
      $$('.tab[data-tab]').forEach(x => x.classList.toggle('active', x === t));
      $$('.tab-panel').forEach(p => p.classList.toggle('active', p.id === 'tab-' + t.dataset.tab));
      renderAdmin();
    }));

    $('#empForm').addEventListener('submit', e => { e.preventDefault(); addEmployee(e.target); });
    $('#empTable').addEventListener('click', e => {
      const b = e.target.closest('button[data-act]');
      if (b) employeeAction(b.dataset.act, b.dataset.id);
    });
    $('#logDate').addEventListener('change', renderLog);
    $('#exportBtn').addEventListener('click', exportCsv);
    $('#logTable').addEventListener('click', e => {
      if (e.target.matches('img[data-full]')) window.open().document.write(`<img src="${e.target.src}" style="width:100%">`);
    });
    $('#settingsForm').addEventListener('submit', e => { e.preventDefault(); saveSettings(e.target); });
  }

  function tickClock() {
    $('#clock').textContent = new Date().toLocaleString('es', { weekday: 'short', hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  buildKeypad();
  bind();
  applyStoreName();
  tickClock();
  setInterval(tickClock, 1000);
  showView('kiosk');
})();
