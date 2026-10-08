// inicio.js: elegir cuenta. El cliente ve sus cuentas; el administrador ve todas, con buscador.
(async () => {
  const ctx = await arrancar('inicio', false);
  if (!ctx) return;
  const { usuario, cuentas } = ctx;
  const admin = esAdmin(usuario);

  $('titulo').textContent = `Hola, ${usuario.UserName}`;
  $('subtitulo').textContent = admin
    ? 'Tiene acceso de administrador a todas las cuentas de ahorro.'
    : 'Estas son las cuentas de ahorro a las que tiene acceso.';
  $('tituloCuentas').textContent = admin ? 'Cuentas de ahorro del sistema' : 'Mis cuentas';
  $('avisoAdmin').hidden = !admin;

  const contenido = $('contenido');
  if (cuentas.length === 0) {
    contenido.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('card')}</span>
      <h3>No tiene cuentas asociadas</h3><p>Comuníquese con su sucursal para que le asocien una cuenta de ahorro.</p></div>`;
    return;
  }

  // Estado de los porcentajes por cuenta (se revisan hasta 12 cuentas)
  const estado = {}; // IdCuenta -> { suma, mostrarAlerta }
  await Promise.allSettled(cuentas.slice(0, 12).map(async (c) => {
    const r = await Api.beneficiarios(c.IdCuenta);
    if (r.exito && r.alerta) estado[c.IdCuenta] = r.alerta;
  }));

  const conAlerta = cuentas.filter(c => estado[c.IdCuenta] && estado[c.IdCuenta].mostrarAlerta);
  if (conAlerta.length) {
    $('alertaTexto').textContent = TEXTO_ALERTA.charAt(0).toUpperCase() + TEXTO_ALERTA.slice(1) + '.';
    $('alertaLista').textContent = 'Cuentas afectadas: ' +
      conAlerta.map(c => `${c.NumeroCuenta} (${estado[c.IdCuenta].suma}%)`).join(', ');
    $('alertaCuentas').hidden = false;
  }

  const insignia = (c) => {
    const e = estado[c.IdCuenta];
    if (!e) return '';
    return e.mostrarAlerta
      ? `<span class="insignia mal">${icono('alert')} Beneficiarios suman ${e.suma}%</span>`
      : `<span class="insignia ok">${icono('check')} Beneficiarios suman 100%</span>`;
  };

  function irA(id, destino) { elegirCuenta(id); window.location.href = destino; }

  function pintarCuentas(lista) {
    if (!lista.length) {
      contenido.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('search')}</span>
        <h3>Sin resultados</h3><p>Ninguna cuenta coincide con la búsqueda.</p></div>`;
      return;
    }
    if (admin) {
      contenido.innerHTML = `<div class="tabla-wrap"><table>
        <thead><tr><th>Cuenta</th><th>Dueño</th><th>Tipo</th><th class="num">Saldo</th><th>Beneficiarios</th><th>Acciones</th></tr></thead>
        <tbody>${lista.map(c => `
          <tr>
            <td class="nowrap"><strong>${escapar(c.NumeroCuenta)}</strong></td>
            <td>${escapar(c.NombreDueno)}</td>
            <td>${escapar(c.TipoCuenta)}</td>
            <td class="num nowrap">${escapar(dinero(c.Saldo, c.Simbolo))}</td>
            <td>${insignia(c) || '—'}</td>
            <td><div class="acciones">
              <button class="btn chico primario" data-ir="beneficiarios.html" data-id="${c.IdCuenta}">Beneficiarios</button>
              <button class="btn chico secundario" data-ir="estados.html" data-id="${c.IdCuenta}">Estados de cuenta</button>
            </div></td>
          </tr>`).join('')}</tbody></table></div>`;
    } else {
      contenido.innerHTML = `<div class="cuentas-grid">${lista.map(c => `
        <article class="cuenta-card ${c.IdCuenta === cuentaGuardada() ? 'sel' : ''}">
          <div class="cuenta-card-cab"><strong>${escapar(c.NumeroCuenta)}</strong><span>${escapar(c.TipoCuenta)}</span></div>
          <div class="cuenta-card-cuerpo">
            ${insignia(c)}
            <div class="cuenta-saldo">${escapar(dinero(c.Saldo, c.Simbolo))}</div>
            <dl>
              <div class="completo"><dt>Dueño</dt><dd>${escapar(c.NombreDueno)}</dd></div>
              <div><dt>Fecha de apertura</dt><dd>${fechaLarga(c.FechaCreacion)}</dd></div>
            </dl>
          </div>
          <div class="cuenta-card-pie">
            <button class="btn primario" data-ir="beneficiarios.html" data-id="${c.IdCuenta}">${icono('users')} Beneficiarios</button>
            <button class="btn secundario" data-ir="estados.html" data-id="${c.IdCuenta}">${icono('file')} Estados de cuenta</button>
          </div>
        </article>`).join('')}</div>`;
    }
  }

  contenido.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-ir]');
    if (b) irA(Number(b.dataset.id), b.dataset.ir);
  });

  if (admin) {
    $('buscadorBox').hidden = false;
    $('buscador').addEventListener('input', (e) => {
      const q = e.target.value.trim().toLowerCase();
      pintarCuentas(cuentas.filter(c => c.NumeroCuenta.toLowerCase().includes(q) || c.NombreDueno.toLowerCase().includes(q)));
    });
  }
  pintarCuentas(cuentas);
})();