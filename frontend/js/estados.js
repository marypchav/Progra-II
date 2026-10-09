// estados.js: lista de los últimos 8 estados de cuenta (más reciente primero)
(async () => {
  const ctx = await arrancar('estados', true);
  if (!ctx) return;
  const cuenta = ctx.cuenta;
  const s = cuenta.Simbolo;

  async function cargar() {
    $('cuerpo').innerHTML = '<div class="cargando">Consultando estados de cuenta...</div>';
    let r;
    try { r = await Api.estados(cuenta.IdCuenta); }
    catch (e) { pintarError($('cuerpo'), 'No hay conexión con el servidor. Revise que esté encendido.', cargar); return; }
    if (!r.exito) { pintarError($('cuerpo'), r.mensaje, cargar); return; }

    const lista = r.estados || [];
    if (lista.length === 0) {
      $('cuerpo').innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('file')}</span>
        <h3>Sin estados de cuenta</h3><p>Esta cuenta todavía no tiene estados de cuenta emitidos.</p></div>`;
      return;
    }

    // El orden ya viene del servidor (fecha de emisión descendente); aquí no se reordena.
    $('cuerpo').innerHTML = `
      <div class="tabla-wrap"><table>
        <thead><tr>
          <th>Fecha del estado</th><th>Período</th>
          <th class="num">Saldo inicial</th><th class="num">Saldo final</th><th class="num">Saldo mínimo</th>
          <th class="num">Intereses acumulados</th><th class="num">Retiros</th><th class="num">Depósitos</th>
          <th class="num">SINPE móvil entrantes</th><th class="num">SINPE móvil salientes</th>
        </tr></thead>
        <tbody>${lista.map(x => `
          <tr class="clic" data-id="${x.IdEstadoCuenta}" title="Los movimientos del mes estarán disponibles en la próxima fase">
            <td class="nowrap">${fechaLarga(x.FechaEmision)}</td>
            <td class="nowrap">${fechaLarga(x.FechaInicio)} al ${fechaLarga(x.FechaFin)}</td>
            <td class="num nowrap">${escapar(dinero(x.SaldoInicial, s))}</td>
            <td class="num nowrap">${escapar(dinero(x.SaldoFinal, s))}</td>
            <td class="num nowrap">${escapar(dinero(x.SaldoMinimo, s))}</td>
            <td class="num nowrap">${escapar(dinero(x.InteresesAcumulados, s))}</td>
            <td class="num">${x.CantRetiros ?? 0}</td>
            <td class="num">${x.CantDepositos ?? 0}</td>
            <td class="num">${x.CantSinpeEntrantes ?? 0}</td>
            <td class="num">${x.CantSinpeSalientes ?? 0}</td>
          </tr>`).join('')}</tbody></table></div>
      <p class="nota-pie">${icono('info')} Cada línea es un estado de cuenta. El detalle de movimientos del mes se mostrará en una próxima fase.</p>`;
    // Cada fila es cliqueable, pero en esta fase hacer clic no hace nada (TP3: mostrar movimientos del mes).
  }

  await cargar();
})();