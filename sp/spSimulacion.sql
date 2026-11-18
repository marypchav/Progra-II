CREATE OR ALTER PROCEDURE dbo.spSimulacion
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución (corrida completa):
    DECLARE @resultado INT;

    EXEC dbo.spLimpiarBD @outResultCode = @resultado OUTPUT;
    EXEC dbo.spCargarCatalogo @outResultCode = @resultado OUTPUT;
    EXEC dbo.spCargarOperacionesXML @outResultCode = @resultado OUTPUT;
    EXEC dbo.spSimulacion @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @fechaInicio DATE
            , @fechaFin DATE
            , @fechaActual DATE
            , @ultimaTerminada DATE
            , @resultadoFecha INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @resultadoFecha = 0;

        -- preprocesamiento: rango de fechas del XML
        SELECT @fechaInicio = MIN(OX.FechaOperacion)
            , @fechaFin = MAX(OX.FechaOperacion)
        FROM dbo.OperacionXML AS OX;

        -- validaciones
        IF (@fechaInicio IS NULL)
        BEGIN
            SET @outResultCode = 52017; -- no se ha cargado el XML de operaciones
            RETURN;
        END;

        -- última fecha terminada (las fechas se terminan en orden)
        SELECT @ultimaTerminada = MAX(CS.FechaOperacion)
        FROM dbo.ControlSimulacion AS CS
        WHERE (CS.FlagTerminado = @true);

        IF (@ultimaTerminada >= @fechaFin)
        BEGIN
            SET @outResultCode = 52018; -- la simulación ya terminó
            RETURN;
        END;

        -- reinicio: se arranca en la primera fecha no terminada
        SET @fechaActual = ISNULL(DATEADD(DAY, 1, @ultimaTerminada), @fechaInicio);

        -- ciclo por fechas, día por día. cada fecha maneja sus propias
        -- transacciones (por nodo y por cierre), por eso aquí no hay una
        WHILE (@fechaActual <= @fechaFin)
        BEGIN

            EXEC dbo.spProcesarFecha
                @inFechaOperacion = @fechaActual
                , @outResultCode = @resultadoFecha OUTPUT;

            IF (@resultadoFecha <> 0)
            BEGIN
                SET @outResultCode = @resultadoFecha; -- se detiene en la fecha que falló
                RETURN;
            END;

            SET @fechaActual = DATEADD(DAY, 1, @fechaActual);

        END;

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