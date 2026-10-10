// beneficiarios.js: lista de beneficiarios, alerta de porcentajes, eliminar (lógico) y límite de 3
(async () => {
  const ctx = await arrancar('beneficiarios', true);
  if (!ctx) return;
  const cuenta = ctx.cuenta;
  let beneficiarios = [];
  let tiposDoc = [];

  async function cargar() {
    $('cuerpo').innerHTML = '<div class="cargando">Cargando beneficiarios...</div>';
    let cat, r;
    try {
      [cat, r] = await Promise.all([Api.catalogos(), Api.beneficiarios(cuenta.IdCuenta)]);
    } catch (e) {
      pintarError($('cuerpo'), 'No hay conexión con el servidor. Revise que esté encendido.', cargar);
      return;
    }
    if (!r.exito) { pintarError($('cuerpo'), r.mensaje, cargar); return; }
    tiposDoc = cat.tiposDocumento || [];
    beneficiarios = r.beneficiarios || [];
    pintarTodo(r.alerta);
  }

  function pintarAlerta(a) {
    if (a && a.mostrarAlerta) {
      $('textoAlerta').textContent = TEXTO_ALERTA;
      $('sumaActual').textContent = `Suma actual: ${a.suma}% de 100%`;
      $('alertaPorc').hidden = false;
    } else {
      $('alertaPorc').hidden = true;
    }
  }

  function nombreTipoDoc(id) {
    const t = tiposDoc.find(x => x.IdTipoDocuIdentidad === id);
    return t ? t.Nombre : '';
  }

  function pintarTodo(alerta) {
    pintarAlerta(alerta);
    const n = beneficiarios.length;
    $('subCab').textContent = `${n} de 3 beneficiarios activos`;

    const suma = alerta ? alerta.suma : beneficiarios.reduce((s, b) => s + b.Porcentaje, 0);
    const tramos = beneficiarios.map((b, i) =>
      `<div class="tramo k${i % 4}" style="width:${Math.min(b.Porcentaje, 100)}%" title="${escapar(b.Nombre)}: ${b.Porcentaje}%"></div>`).join('');
    let leyenda = beneficiarios.map((b, i) =>
      `<span><i class="punto k${i % 4}"></i>${escapar(b.Nombre)} · ${b.Porcentaje}%</span>`).join('');
    if (suma < 100) leyenda += `<span><i class="punto kotro"></i>Sin asignar · ${100 - suma}%</span>`;
    if (suma > 100) leyenda += `<span>Excede por ${suma - 100}%</span>`;

    const distribucion = `
      <div class="distribucion">
        <div class="distribucion-cab">
          <h3>Reparto del saldo entre beneficiarios</h3>
          <span class="total ${suma === 100 ? 'ok' : 'mal'}">${suma}% de 100%</span>
        </div>
        <div class="barra-dist ${suma > 100 ? 'excede' : ''}" role="img" aria-label="Porcentaje asignado: ${suma} por ciento">${tramos}</div>
        <div class="leyenda">${leyenda}</div>
      </div>`;

    if (n === 0) {
      $('cuerpo').innerHTML = distribucion + `
        <div class="estado-vacio"><span class="estado-ico">${icono('userPlus')}</span>
          <h3>Aún no tiene beneficiarios</h3>
          <p>Agregue hasta 3 personas para repartir su saldo entre ellas. La suma de sus porcentajes debe ser 100.</p>
          <div class="estado-acc"><button class="btn primario" id="btnAgregarVacio" type="button">Agregar beneficiario</button></div>
        </div>`;
      $('btnAgregarVacio').addEventListener('click', agregar);
      return;
    }

    $('cuerpo').innerHTML = distribucion + `
      <div class="tabla-wrap"><table>
        <thead><tr>
          <th>Beneficiario</th><th>Parentesco</th><th class="num">Porcentaje</th><th>Documento</th>
          <th>Nacimiento</th><th>Email</th><th>Teléfonos</th><th>Acciones</th>
        </tr></thead>
        <tbody>${beneficiarios.map((b, i) => `
          <tr>
            <td><div class="nombre-celda"><span class="avatar" aria-hidden="true">${escapar(iniciales(b.Nombre))}</span>
              <div><strong>${escapar(b.Nombre)}</strong></div></div></td>
            <td><span class="chip">${escapar(b.Parentesco)}</span></td>
            <td class="num"><span class="pct">${b.Porcentaje}%</span></td>
            <td><strong>${escapar(b.ValorDocumentoIdentidad)}</strong><br><small>${escapar(nombreTipoDoc(b.IdTipoDocuIdentidad))}</small></td>
            <td class="nowrap">${fechaLarga(b.FechaNacimiento)}</td>
            <td>${escapar(b.Email)}</td>
            <td class="nowrap">${escapar(b.Telefono1)}<br>${escapar(b.Telefono2)}</td>
            <td><div class="acciones">
              <button class="btn chico secundario" data-accion="editar" data-id="${b.IdBeneficiario}">${icono('edit')} Editar</button>
              <button class="btn chico peligro" data-accion="eliminar" data-id="${b.IdBeneficiario}">${icono('trash')} Eliminar</button>
            </div></td>
          </tr>`).join('')}</tbody></table></div>
      <p class="nota-pie">${icono('info')} Al eliminar un beneficiario queda inactivo (no se borra) y se guarda la fecha de desactivación.</p>`;
  }

  // ---- agregar: si ya hay 3, se muestra el aviso de límite ----
  async function agregar() {
    if (beneficiarios.length >= 3) {
      await modal({
        tipo: 'aviso', titulo: 'Límite de beneficiarios',
        mensaje: 'Una cuenta no puede tener más de 3 beneficiarios activos.',
        detalle: 'Elimine un beneficiario si desea agregar otro.', textoOk: 'Entendido'
      });
      return;
    }
    window.location.href = 'beneficiario.html';
  }
  $('btnAgregar').addEventListener('click', agregar);

  // ---- editar / eliminar ----
  $('cuerpo').addEventListener('click', async (e) => {
    const btn = e.target.closest('button[data-accion]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const b = beneficiarios.find(x => x.IdBeneficiario === id);
    if (!b) return;

    if (btn.dataset.accion === 'editar') {
      window.location.href = 'beneficiario.html?id=' + id;
      return;
    }

    const si = await modal({
      tipo: 'peligro', titulo: 'Eliminar beneficiario',
      mensaje: `¿Desea eliminar a ${b.Nombre} (${b.Porcentaje}%)?`,
      detalle: 'Quedará inactivo y su porcentaje dejará de contar. Si la suma deja de ser 100, se mostrará una alerta para que la corrija.',
      textoOk: 'Sí, eliminar', textoCancelar: 'Cancelar'
    });
    if (!si) return;

    btn.disabled = true;
    let r;
    try { r = await Api.eliminar(id); } catch (err) { r = { exito: false, mensaje: 'No hay conexión con el servidor.' }; }
    if (r.exito) {
      toast('Beneficiario eliminado.', 'ok');
      await cargar();
    } else {
      btn.disabled = false;
      await modal({ tipo: 'error', titulo: 'No se pudo eliminar', mensaje: r.mensaje, textoOk: 'Cerrar' });
      await cargar();
    }
  });

  await cargar();
})();