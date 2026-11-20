/*
pruebaReinicio.sql
Prueba de la sección Cuatro: si la simulación falla a la mitad, al volver a
correrla continúa desde la última PK procesada, sin repetir nada.
*/

DECLARE @r INT
    , @idNodoMalo INT
    , @inicio DATETIME = GETDATE();

DECLARE @resultados TABLE (
    Paso VARCHAR(80)
    , Esperado VARCHAR(20)
    , Obtenido VARCHAR(20)
);

-- preparación: base limpia, catálogos y XML cargado
EXEC dbo.spLimpiarBD @r OUTPUT;
EXEC dbo.spCargarCatalogo @r OUTPUT;
EXEC dbo.spCargarOperacionesXML @r OUTPUT;

-- se daña el nodo
SELECT @idNodoMalo = OX.IdOperacionXML
FROM dbo.OperacionXML AS OX
WHERE (OX.FechaOperacion = '2026-03-10')
    AND (OX.TipoNodo = 'Movimientos')
    AND (OX.Nodo.value('(/Movimientos/@CodigoCuenta)[1]', 'VARCHAR(20)') = '21000001');

UPDATE dbo.OperacionXML
SET Nodo.modify('replace value of (/Movimientos/@Monto)[1] with "abc"')
WHERE (IdOperacionXML = @idNodoMalo);

-- 1. la simulación se cae en el nodo dañado
EXEC dbo.spSimulacion @r OUTPUT;
INSERT INTO @resultados VALUES ('1 Simulacion con nodo dañado', '50000', CAST(@r AS VARCHAR(20)));

-- 2. hasta dónde llegó: 2026-03-10 sin terminar, con el último nodo bueno anterior al dañado
INSERT INTO @resultados
SELECT '2 Ultima fecha terminada'
    , '2026-03-09'
    , CONVERT(VARCHAR(10), MAX(CS.FechaOperacion), 23)
FROM dbo.ControlSimulacion AS CS
WHERE (CS.FlagTerminado = 1);

INSERT INTO @resultados
SELECT '3 Ultimo nodo procesado del 2026-03-10'
    , CAST(@idNodoMalo - 1 AS VARCHAR(20))
    , CAST(CS.UltimoIdOperacionXML AS VARCHAR(20))
FROM dbo.ControlSimulacion AS CS
WHERE (CS.FechaOperacion = '2026-03-10');

-- se arregla el nodo y se vuelve a correr
UPDATE dbo.OperacionXML
SET Nodo.modify('replace value of (/Movimientos/@Monto)[1] with "1500.00"')
WHERE (IdOperacionXML = @idNodoMalo);

-- 4. la simulación continúa desde ese nodo y termina
EXEC dbo.spSimulacion @r OUTPUT;
INSERT INTO @resultados VALUES ('4 Simulacion despues de arreglar', '0', CAST(@r AS VARCHAR(20)));

-- 5. no se repitió nada: el depósito de apertura de 11000005 (mismo día, antes
-- del nodo dañado) debe existir una sola vez
INSERT INTO @resultados
SELECT '5 Depositos del 2026-03-10 en 11000005'
    , '1'
    , CAST(COUNT(1) AS VARCHAR(20))
FROM dbo.Movimiento AS M
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = M.IdCuenta)
WHERE (C.NumeroCuenta = '11000005')
    AND (M.Fecha = '2026-03-10')
    AND (M.IdTipoMovimiento = 1);

-- 6. todas las fechas quedaron terminadas
INSERT INTO @resultados
SELECT '6 Fechas terminadas'
    , '122'
    , CAST(COUNT(1) AS VARCHAR(20))
FROM dbo.ControlSimulacion AS CS
WHERE (CS.FlagTerminado = 1);

-- 7. volver a correrla no hace nada
EXEC dbo.spSimulacion @r OUTPUT;
INSERT INTO @resultados VALUES ('7 Simulacion ya terminada', '52018', CAST(@r AS VARCHAR(20)));

-- resumen: Ok = 1 en todas las filas
SELECT R.Paso
    , R.Esperado
    , R.Obtenido
    , CASE WHEN (R.Esperado = R.Obtenido) THEN 1 ELSE 0 END AS Ok
FROM @resultados AS R;

-- el error de la caída quedó registrado (una sola fila, de spProcesarFecha)
SELECT E.ErrorNumber
    , E.ErrorProcedure
    , E.ErrorMessage
    , E.ErrorDateTime
FROM dbo.dbError AS E
WHERE (E.ErrorDateTime >= @inicio)
ORDER BY E.ErrorDateTime;
