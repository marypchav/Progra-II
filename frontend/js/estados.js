// estados.js: consulta de estados de cuenta (del más reciente al más antiguo) y detalle cronológico de movimientos.
(async () => {
  const ctx = await arrancar('estados', true);
  if (!ctx) return;
  const { cuenta } = ctx;
  const contenido = $('contenido');
  const seccionDetalle = $('seccionDetalle');
  const contenidoDetalle = $('contenidoDetalle');
  const sim = cuenta.Simbolo;

  let estados = [];
  let idSeleccionado = null;
  let movimientosActuales = [];
  let estadoActual = null;
  let filtroAccion = 'todos';
  let textoBusqueda = '';

  const num = (v, simboloMoneda) =>
    v === null || v === undefined ? '—' : escapar(dinero(v, simboloMoneda || sim));

  const cantATM = (e) => e.CantOperATM ?? e.CantRetiros ?? 0;
  const cantVentana = (e) => e.CantOperVentana ?? e.CantDepositos ?? 0;
  const cantSinpe = (e) =>
    e.CantOperSinpe ?? ((e.CantSinpeEntrantes || 0) + (e.CantSinpeSalientes || 0));

  const estaAbierto = (e) =>
    e.FlagAbierto === true || e.FlagAbierto === 1 || !e.FechaEmision;

  const textoFechaEstado = (e) => {
    if (e.FechaEmision) return fechaLarga(e.FechaEmision);
    if (e.FechaFin) return fechaLarga(e.FechaFin);
    return 'En curso';
  };

  const insigniaEstado = (e) =>
    estaAbierto(e)
      ? `<span class="estado-badge abierto">${icono('calendar')} Abierto</span>`
      : `<span class="estado-badge cerrado">${icono('check')} Cerrado</span>`;

  // ---------- Cargar lista de estados de cuenta ----------
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

  estados = r.estados || [];
  if (!estados.length) {
    contenido.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('file')}</span>
      <h3>Sin estados de cuenta</h3><p>Esta cuenta todavía no tiene estados de cuenta registrados.</p></div>`;
    return;
  }

  function pintarTablaEstados() {
    contenido.innerHTML = `<div class="tabla-wrap"><table>
      <thead><tr>
        <th>Fecha</th>
        <th>Período</th>
        <th>Estado</th>
        <th class="num">Saldo al inicio</th>
        <th class="num">Saldo al final</th>
        <th class="num">Saldo mínimo</th>
        <th class="centro">Oper. ATM</th>
        <th class="centro">Cajero humano</th>
        <th class="centro">Oper. SINPE</th>
        <th class="num">Acción</th>
      </tr></thead>
      <tbody>${estados.map((e) => {
        const activo = e.IdEstadoCuenta === idSeleccionado ? ' fila-activa' : '';
        return `
        <tr class="clic${activo}" data-id="${e.IdEstadoCuenta}">
          <td class="nowrap"><strong>${textoFechaEstado(e)}</strong></td>
          <td class="nowrap">${fechaLarga(e.FechaInicio)} – ${fechaLarga(e.FechaFin)}</td>
          <td class="nowrap">${insigniaEstado(e)}</td>
          <td class="num nowrap">${num(e.SaldoInicial)}</td>
          <td class="num nowrap">${num(e.SaldoFinal)}</td>
          <td class="num nowrap">${num(e.SaldoMinimo)}</td>
          <td class="centro"><span class="cont-pill">${cantATM(e)}</span></td>
          <td class="centro"><span class="cont-pill">${cantVentana(e)}</span></td>
          <td class="centro"><span class="cont-pill">${cantSinpe(e)}</span></td>
          <td class="num nowrap">
            <button type="button" class="btn chico ${e.IdEstadoCuenta === idSeleccionado ? 'primario' : 'secundario'}" data-ver="${e.IdEstadoCuenta}">
              ${icono('eye')} Consultar
            </button>
          </td>
        </tr>`;
      }).join('')}</tbody></table></div>
      <p class="nota-pie">${icono('info')} Seleccione cualquier estado de cuenta de la tabla para consultar su resumen y el detalle cronológico de sus movimientos.</p>`;
  }

  // ---------- Consulta de un estado de cuenta y sus movimientos ----------
  async function seleccionarEstado(idEstado) {
    const estadoBase = estados.find((x) => x.IdEstadoCuenta === idEstado);
    if (!estadoBase) return;

    idSeleccionado = idEstado;
    pintarTablaEstados();

    seccionDetalle.hidden = false;
    $('detalleTitulo').textContent = `Estado de cuenta · ${fechaLarga(estadoBase.FechaInicio)} al ${fechaLarga(estadoBase.FechaFin)}`;
    $('detalleSub').textContent = estaAbierto(estadoBase)
      ? 'Período actualmente abierto · Movimientos registrados hasta la fecha.'
      : `Estado cerrado el ${textoFechaEstado(estadoBase)} · Detalle de movimientos en orden cronológico.`;

    contenidoDetalle.innerHTML = `<div class="cargando">Cargando detalle y movimientos del estado de cuenta...</div>`;
    seccionDetalle.scrollIntoView({ behavior: 'smooth', block: 'start' });

    let resMov;
    try {
      resMov = await Api.movimientos(idEstado);
    } catch (err) {
      resMov = null;
    }

    if (!resMov || !resMov.exito) {
      contenidoDetalle.innerHTML = `<div class="estado-vacio error"><span class="estado-ico">${icono('xcircle')}</span>
        <h3>No se pudo consultar el detalle del estado</h3>
        <p>${escapar(resMov ? resMov.mensaje : 'Error de conexión con el servidor.')}</p></div>`;
      return;
    }

    estadoActual = resMov.estado || estadoBase;
    movimientosActuales = resMov.movimientos || [];
    filtroAccion = 'todos';
    textoBusqueda = '';

    pintarDetalleEstado();
  }

  function pintarDetalleEstado() {
    const e = estadoActual;
    const simboloEstado = e.Simbolo || sim;

    const resumenHTML = `
      <div class="resumen-estado-grid">
        <div class="kpi-card destacado">
          <span class="kpi-etiqueta">${icono('calendar')} Fecha del estado</span>
          <strong class="kpi-valor">${textoFechaEstado(e)}</strong>
          <span class="kpi-sub">Período: ${fechaLarga(e.FechaInicio)} – ${fechaLarga(e.FechaFin)}</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">Saldo al inicio</span>
          <strong class="kpi-valor">${num(e.SaldoInicial, simboloEstado)}</strong>
          <span class="kpi-sub">Apertura del período</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">Saldo al final</span>
          <strong class="kpi-valor">${num(e.SaldoFinal, simboloEstado)}</strong>
          <span class="kpi-sub">${estaAbierto(e) ? 'Saldo acumulado actual' : 'Saldo al cierre'}</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">Saldo mínimo</span>
          <strong class="kpi-valor">${num(e.SaldoMinimo, simboloEstado)}</strong>
          <span class="kpi-sub">Mínimo registrado en el mes</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">${icono('card')} Operaciones en ATM</span>
          <strong class="kpi-valor">${cantATM(e)}</strong>
          <span class="kpi-sub">Cajero automático</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">${icono('users')} Cajero humano</span>
          <strong class="kpi-valor">${cantVentana(e)}</strong>
          <span class="kpi-sub">Operaciones en ventana</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-etiqueta">${icono('smartphone')} Operaciones SINPE</span>
          <strong class="kpi-valor">${cantSinpe(e)}</strong>
          <span class="kpi-sub">Transferencias SINPE</span>
        </div>
      </div>

      <div class="mov-cabecera-sec">
        <h3>${icono('activity')} Detalle de movimientos (orden cronológico)</h3>
        <div class="mov-controles">
          <div class="filtro-grupo" role="group" aria-label="Filtrar por tipo de movimiento">
            <button type="button" class="filtro-btn active-f" data-filtro="todos">Todos (${movimientosActuales.length})</button>
            <button type="button" class="filtro-btn" data-filtro="Credito">Créditos (+)</button>
            <button type="button" class="filtro-btn" data-filtro="Debito">Débitos (−)</button>
            <button type="button" class="filtro-btn" data-filtro="sinpe">SINPE</button>
          </div>
          <div class="buscador">
            <span data-ico="search"></span>
            <input id="buscarMov" type="search" placeholder="Buscar por descripción o tipo..." aria-label="Buscar movimiento">
          </div>
        </div>
      </div>
      <div id="tablaMovimientosWrap"></div>`;

    contenidoDetalle.innerHTML = resumenHTML;
    pintarIconos(contenidoDetalle);
    actualizarBotonesFiltro();
    pintarTablaMovimientos();

    const inputBuscar = $('buscarMov');
    if (inputBuscar) {
      inputBuscar.addEventListener('input', (ev) => {
        textoBusqueda = ev.target.value.trim().toLowerCase();
        pintarTablaMovimientos();
      });
    }

    contenidoDetalle.querySelectorAll('button[data-filtro]').forEach((btn) => {
      btn.addEventListener('click', () => {
        filtroAccion = btn.dataset.filtro;
        actualizarBotonesFiltro();
        pintarTablaMovimientos();
      });
    });
  }

  function actualizarBotonesFiltro() {
    contenidoDetalle.querySelectorAll('button[data-filtro]').forEach((btn) => {
      btn.classList.toggle('activo', btn.dataset.filtro === filtroAccion);
    });
  }

  function pintarTablaMovimientos() {
    const wrap = $('tablaMovimientosWrap');
    if (!wrap) return;
    const simboloEstado = (estadoActual && estadoActual.Simbolo) || sim;

    if (!movimientosActuales.length) {
      wrap.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('file')}</span>
        <h3>Sin movimientos en este estado</h3>
        <p>No se registraron movimientos durante el período de este estado de cuenta.</p></div>`;
      return;
    }

    const filtrados = movimientosActuales.filter((m) => {
      const tipoTxt = String(m.TipoMovimiento || '').toLowerCase();
      const descTxt = String(m.Descripcion || '').toLowerCase();
      const cumpleAccion =
        filtroAccion === 'todos'
          ? true
          : filtroAccion === 'sinpe'
            ? tipoTxt.includes('sinpe') || descTxt.includes('sinpe')
            : String(m.Accion || '').toLowerCase() === filtroAccion.toLowerCase();
      const q = textoBusqueda;
      const cumpleTexto =
        !q ||
        descTxt.includes(q) ||
        tipoTxt.includes(q) ||
        fechaLarga(m.Fecha).includes(q);
      return cumpleAccion && cumpleTexto;
    });

    if (!filtrados.length) {
      wrap.innerHTML = `<div class="estado-vacio"><span class="estado-ico">${icono('search')}</span>
        <h3>Sin coincidencias</h3>
        <p>Ningún movimiento coincide con el filtro seleccionado.</p></div>`;
      return;
    }

    wrap.innerHTML = `<div class="tabla-wrap"><table>
      <thead><tr>
        <th>Fecha del movimiento</th>
        <th>Descripción del movimiento</th>
        <th>Tipo</th>
        <th class="num">Monto (${escapar(simboloEstado)})</th>
        <th class="num">Nuevo saldo</th>
      </tr></thead>
      <tbody>${filtrados.map((m) => {
        const esCredito = String(m.Accion || '').toLowerCase() === 'credito';
        const signo = esCredito ? '+' : '−';
        const claseMov = esCredito ? 'credito' : 'debito';
        const icoMov = esCredito ? icono('arrowDownLeft') : icono('arrowUpRight');
        return `
        <tr>
          <td class="nowrap"><strong>${fechaLarga(m.Fecha)}</strong></td>
          <td>${escapar(m.Descripcion || '—')}</td>
          <td class="nowrap">
            <span class="chip-mov ${claseMov}">${icoMov} ${escapar(m.TipoMovimiento || (esCredito ? 'Crédito' : 'Débito'))}</span>
          </td>
          <td class="num"><span class="mov-monto ${claseMov}">${signo} ${num(m.Monto, simboloEstado)}</span></td>
          <td class="num"><span class="mov-saldo">${num(m.NuevoSaldo, simboloEstado)}</span></td>
        </tr>`;
      }).join('')}</tbody></table></div>
      <p class="nota-pie">${icono('info')} Mostrando ${filtrados.length} de ${movimientosActuales.length} movimientos en orden cronológico.</p>`;
  }

  // ---------- Eventos ----------
  contenido.addEventListener('click', (e) => {
    const fila = e.target.closest('tr[data-id]');
    if (!fila) return;
    seleccionarEstado(Number(fila.dataset.id));
  });

  $('btnCerrarDetalle').addEventListener('click', () => {
    idSeleccionado = null;
    seccionDetalle.hidden = true;
    pintarTablaEstados();
  });

  pintarTablaEstados();
})();
