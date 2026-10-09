// estados.js: últimos 8 estados de cuenta de la cuenta elegida (más reciente primero).
(async () => {
  const ctx = await arrancar('estados', true);
  if (!ctx) return;
  const { cuenta } = ctx;
  const contenido = $('contenido');
  const sim = cuenta.Simbolo;

  const num = (v) => (v === null || v === undefined ? '—' : escapar(dinero(v, sim)));

  let r;
  try {
    r = await Api.estados(cuenta.IdCuenta);
  } catch (e) {
    r = null;
  }

  if (!r) {
    contenido.innerHTML = `<div class="estado-vacio error"><span class="estado-ico">${icono('xcircle')}</span>
      <h3>No se pudo conectar</h3><p>Revise que el servidor esté encendido e intente de nuevo.</p>
      <div class="estado-acc"><button class="btn primario" onclick="location.reload()">Reintentar</button></div></div>`;
    return;
  }
  if (!r.exito) {
    contenido.innerHTML = `<div class="estado-vacio error"><span class="estado-ico">${icono('xcircle')}</span>
      <h3>No se pudieron cargar los estados</h3><p>${escapar(r.mensaje)}</p></div>`;
    return;
  }

  const estados = r.estados || [];
  if (!estados.length) {
    contenido.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('file')}</span>
      <h3>Sin estados de cuenta</h3><p>Esta cuenta todavía no tiene estados emitidos.</p></div>`;
    return;
  }

  contenido.innerHTML = `<div class="tabla-wrap"><table>
    <thead><tr>
      <th>Fecha de emisión</th><th>Período</th>
      <th class="num">Saldo inicial</th><th class="num">Saldo final</th><th class="num">Saldo mínimo</th>
      <th class="num">Intereses</th><th class="num">Retiros</th><th class="num">Depósitos</th>
      <th class="num">SINPE entrantes</th><th class="num">SINPE salientes</th>
    </tr></thead>
    <tbody>${estados.map(e => `
      <tr class="clic" data-id="${e.IdEstadoCuenta}">
        <td class="nowrap">${fechaLarga(e.FechaEmision)}</td>
        <td class="nowrap">${fechaLarga(e.FechaInicio)} – ${fechaLarga(e.FechaFin)}</td>
        <td class="num nowrap">${num(e.SaldoInicial)}</td>
        <td class="num nowrap">${num(e.SaldoFinal)}</td>
        <td class="num nowrap">${num(e.SaldoMinimo)}</td>
        <td class="num nowrap">${num(e.InteresesAcumulados)}</td>
        <td class="num">${e.CantRetiros ?? '—'}</td>
        <td class="num">${e.CantDepositos ?? '—'}</td>
        <td class="num">${e.CantSinpeEntrantes ?? '—'}</td>
        <td class="num">${e.CantSinpeSalientes ?? '—'}</td>
      </tr>`).join('')}</tbody></table></div>
    <p class="nota-pie">${icono('info')} El detalle de movimientos de cada estado estará disponible en una fase posterior.</p>`;

  // Para esta fase, al dar clic en una fila no pasa nada (TP3 mostrará los movimientos).
})();