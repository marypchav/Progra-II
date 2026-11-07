CREATE OR ALTER PROCEDURE dbo.spCargarOperacionesXML
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCargarOperacionesXML
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes: orden de proceso de cada tipo de nodo dentro de una fecha
        DECLARE @ordenPersona INT = 1
            , @ordenCuenta INT = 2
            , @ordenBeneficiario INT = 3
            , @ordenUsuario INT = 4
            , @ordenUsuarioPuedeVer INT = 5
            , @ordenMovimiento INT = 6
            , @ordenDesconocido INT = 99;

        -- variables de uso general
        DECLARE @datos XML; -- contenido completo del XML

        -- nodos del XML ya separados, antes de pasarlos a la tabla
        DECLARE @Nodos TABLE (
            FechaOperacion DATE
            , Orden INT
            , Posicion INT -- posición del nodo dentro de su FechaOperacion
            , TipoNodo VARCHAR(32)
            , Nodo XML
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- el XML de operaciones se carga una sola vez
        IF EXISTS (
            SELECT 1
            FROM dbo.OperacionXML AS OX
        )
        BEGIN
            SET @outResultCode = 52011; -- el XML ya fue cargado
            RETURN;
        END;

        -- preprocesamiento: lee el archivo como binario (SINGLE_BLOB) y lo
        -- convierte a XML, respetando el UTF-8 declarado (para las tildes)
        SELECT @datos = X.BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\OperacionesTarea3.xml', SINGLE_BLOB) AS X;

        -- un registro por cada nodo hijo de cada FechaOperacion.
        -- local-name(.) da el nombre del nodo (Persona, Cuenta, ...) y la
        -- expresión con "<<" cuenta cuántos nodos hay antes de él (su posición)
        INSERT INTO @Nodos (
            FechaOperacion
            , Orden
            , Posicion
            , TipoNodo
            , Nodo
        )
        SELECT F.Fecha.value('@Fecha', 'DATE')
            , CASE N.Nodo.value('local-name(.)', 'VARCHAR(32)')
                WHEN 'Persona' THEN @ordenPersona
                WHEN 'Cuenta' THEN @ordenCuenta
                WHEN 'Beneficiario' THEN @ordenBeneficiario
                WHEN 'Usuario' THEN @ordenUsuario
                WHEN 'UsuarioPuedeVer' THEN @ordenUsuarioPuedeVer
                WHEN 'Movimientos' THEN @ordenMovimiento
                ELSE @ordenDesconocido
              END
            , N.Nodo.value('for $n in . return count(../*[. << $n]) + 1', 'INT')
            , N.Nodo.value('local-name(.)', 'VARCHAR(32)')
            , N.Nodo.query('.')
        FROM @datos.nodes('/Operaciones/FechaOperacion') AS F(Fecha)
        CROSS APPLY F.Fecha.nodes('*') AS N(Nodo);

        -- el XML no puede venir vacío ni traer nodos que no se saben procesar
        IF NOT EXISTS (
            SELECT 1
            FROM @Nodos AS XN
        )
            OR EXISTS (
                SELECT 1
                FROM @Nodos AS XN
                WHERE (XN.Orden = @ordenDesconocido)
            )
        BEGIN
            SET @outResultCode = 52012; -- XML vacío o con nodos desconocidos
            RETURN;
        END;

        -- transacción: se carga todo el XML o nada
        BEGIN TRANSACTION tCargarOperacionesXML;

            -- el ORDER BY hace que el IDENTITY quede en orden de proceso
            INSERT INTO dbo.OperacionXML (
                FechaOperacion
                , Orden
                , TipoNodo
                , Nodo
            )
            SELECT XN.FechaOperacion
                , XN.Orden
                , XN.TipoNodo
                , XN.Nodo
            FROM @Nodos AS XN
            ORDER BY XN.FechaOperacion
                , XN.Orden
                , XN.Posicion;

        COMMIT TRANSACTION tCargarOperacionesXML;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO